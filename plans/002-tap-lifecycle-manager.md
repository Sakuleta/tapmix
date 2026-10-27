# Plan 002: Own tap lifecycle in TapManager and make health per-tap

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If a
> STOP condition occurs, stop and report — do not improvise.
>
> **Drift check (run first)**: pre-git planning snapshot; compare the SHA-256 hashes below:
> `5233526383d7ccebfb31ece6de4a3ff1e43c5fc6821704dc897254385bbb80c2  Sources/TapmixCore/AudioEngine.swift`
> `e35fee7c092a77c095c144c07a1624e0a398f289a4736a8fcb81f4cd19e0d23f  Sources/TapmixCore/TapController.swift`
> If a hash differs, compare the quotes below against the live code. Plan 001
> changes only `AudioSystem.swift`/`PanelView.swift`, so it must not affect
> these two hashes.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none (execute after 001 for a clean sequence)
- **Category**: bug + tech-debt
- **Planned at**: pre-git snapshot, 2026-10-27
- **Issue**: not published

## Why this matters

`AudioEngine` owns the tap dictionary, a failure map, a global `captureBlocked`
flag and a health check that runs inside the poll loop. One tap with no callbacks
forces `stopAllTaps()` and blocks every future tap until the user presses Retry.
That was observed during first-run permission: the macOS consent prompt took
longer than six seconds, the app tore down its only tap, and granting permission
did not resume control until a manual Retry. The same class also has 0% test
coverage because nothing can cross the real Core Audio seam.

This plan moves lifecycle into a `TapManager` with a small interface and a fake
adapter. Per-tap health replaces the global block; healthy taps survive a
stalled one. It does **not** change the realtime render path (plan 003) or
discovery/grouping (plan 004).

## Current state

`AudioEngine` is `@MainActor` (`AudioEngine.swift:6`). Its lifecycle state is
spread across:

```swift
private var taps: [AudioObjectID: TapController] = [:]
private var failures: [AudioObjectID: Date] = [:]
private var outputUID: String?
private var captureBlocked = false
private var errorMessage: String?
```

The health policy (`AudioEngine.swift:213-227`) is the bug:

```swift
private func checkHealth(playing: Set<AudioObjectID>) {
    guard errorMessage == nil else { return }
    for (objectID, tap) in taps where playing.contains(objectID) {
        guard tap.callbackCount == 0,
              Date().timeIntervalSince(tap.createdAt) > 6
        else { continue }
        stopAllTaps()
        captureBlocked = true
        failures[objectID] = Date()
        errorMessage = "macOS is not delivering audio for “\(tap.bundleID)”. ..."
        return
    }
}
```

Tap creation and failure bookkeeping live in the same loop
(`AudioEngine.swift:185-202`). `TapController` exposes the pieces health needs:

```swift
let processObjectID: AudioObjectID
let bundleID: String
let createdAt = Date()
private(set) var callbackCount: UInt64 = 0
func start() throws
func stop()
func setGain(_ gain: Float)
```

Current behavior to preserve: an app with a stored level or an active tap stays
in the list; a tap is created only when the process is producing audio, but an
existing tap is kept while the process lives. Taps are torn down when the
process disappears, the output device UID changes, or the app quits.

Repo conventions: `@MainActor` for UI-facing state; `AudioSystem` is the only
HAL wrapper; `os.Logger` is used for diagnostics, never in the realtime callback;
tests use `XCTest` and `@testable import TapmixCore`.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `swift build` | exit 0 |
| Focused tests | `swift test --filter TapManagerTests` | all pass |
| Full tests | `swift test` | all pass |
| Release build | `swift build -c release` | exit 0 |
| Manual run | `./scripts/build-app.sh && open build/Tapmix.app` | icon + audio |

## Scope

**In scope**:
- `Sources/TapmixCore/TapManager.swift` (create)
- `Sources/TapmixCore/TapControlling.swift` (create; the protocol may live here)
- `Sources/TapmixCore/TapController.swift` (add conformance only)
- `Sources/TapmixCore/AudioEngine.swift`
- `Tests/TapmixTests/TapManagerTests.swift` (create)

**Out of scope**:
- `TapController.render` / `AudioMath` — plan 003 rewrites the render path.
- `AppResolver`, `AudioCatalog`, `Models` — plan 004.
- Moving `TapController.start()` off the main actor. The manager's seam makes that
  a later, local change; do not add queues now.
- UI layout changes; `PanelView` already renders `errorMessage`.

## Steps

### Step 1: Add the controlling protocol and make TapController conform

Create `Sources/TapmixCore/TapControlling.swift`:

```swift
import CoreAudio
import Foundation

protocol TapControlling: AnyObject {
    var processObjectID: AudioObjectID { get }
    var bundleID: String { get }
    var createdAt: Date { get }
    var callbackCount: UInt64 { get }
    func start() throws
    func stop()
    func setGain(_ gain: Float)
}
```

Change only the class declaration in `TapController.swift:22`:

```swift
final class TapController: TapControlling {
```

Everything else in `TapController` stays. Its existing `private(set) var
callbackCount` satisfies the getter; `createdAt` and `bundleID` are already lets;
`start`, `stop`, `setGain` already match. Do **not** mark `TapController`
`@MainActor`: the IO proc calls `render` from the HAL thread.

**Verify**: `swift build` → exit 0.

### Step 2: Implement TapManager

Create `Sources/TapmixCore/TapManager.swift` with this public shape:

```swift
import CoreAudio
import Foundation

@MainActor
final class TapManager {
    struct DesiredTap: Equatable {
        let processObjectID: AudioObjectID
        let bundleID: String
        let displayName: String
    }

    enum Health: Equatable {
        case ok
        case stalled(displayName: String, message: String)
    }

    typealias TapFactory = (AudioObjectID, String, String) -> any TapControlling

    static let healthWindow: TimeInterval = 6
    static let retryDelays: [TimeInterval] = [15, 30, 60, 120, 300]

    private struct Failure {
        var attempts: Int
        var retryAt: Date
        var bundleID: String
        var displayName: String
        var detail: String
    }

    private let makeTap: TapFactory
    private let now: () -> Date
    private var taps: [AudioObjectID: any TapControlling] = [:]
    private var failures: [AudioObjectID: Failure] = [:]
    private var gains: [String: Float] = [:]
    private var outputUID: String?
    private(set) var health: Health = .ok

    init(
        makeTap: @escaping TapFactory = { processID, bundleID, outputUID in
            TapController(
                processObjectID: processID,
                bundleID: bundleID,
                outputDeviceUID: outputUID
            )
        },
        now: @escaping () -> Date = Date.init
    ) {
        self.makeTap = makeTap
        self.now = now
    }

    var activeProcessIDs: Set<AudioObjectID> { Set(taps.keys) }
    var activeBundleIDs: Set<String> { Set(taps.values.map { $0.bundleID }) }
}
```

Implement the methods exactly as follows (fill in only the obvious dictionary
mechanics):

```swift
func setGain(_ gain: Float, for bundleID: String) {
    let clamped = AudioMath.clampedGain(gain)
    gains[bundleID] = clamped
    for tap in taps.values where tap.bundleID == bundleID {
        tap.setGain(clamped)
    }
}

func sync(desired: [DesiredTap], outputUID: String) {
    let unique = Dictionary(
        desired.map { ($0.processObjectID, $0) },
        uniquingKeysWith: { first, _ in first }
    )
    let desiredIDs = Set(unique.keys)

    if self.outputUID != outputUID {
        stopAllTaps()
        failures.removeAll()
        self.outputUID = outputUID
    }

    let stale = taps.keys.filter { !desiredIDs.contains($0) }
    for id in stale {
        taps[id]?.stop()
        taps[id] = nil
        failures[id] = nil
    }

    for id in desiredIDs {
        guard let desiredTap = unique[id] else { continue }
        if let tap = taps[id] {
            tap.setGain(gains[tap.bundleID] ?? 1)
            continue
        }
        if let failure = failures[id], now() < failure.retryAt {
            continue
        }

        let tap = makeTap(id, desiredTap.bundleID, outputUID)
        do {
            try tap.start()
            tap.setGain(gains[desiredTap.bundleID] ?? 1)
            taps[id] = tap
            failures[id] = nil
        } catch {
            recordFailure(for: desiredTap, detail: error.localizedDescription)
        }
    }

    checkHealth(desired: unique)
    recomputeHealth()
}

func retry() {
    failures.removeAll()
    health = .ok
}

func stopAll() {
    stopAllTaps()
    failures.removeAll()
    health = .ok
}
```

Private helpers:

```swift
private func stopAllTaps() {
    for tap in taps.values { tap.stop() }
    taps.removeAll()
}

private func checkHealth(desired: [AudioObjectID: DesiredTap]) {
    // Collect first: never mutate `taps` while iterating it.
    var stalled: [AudioObjectID] = []
    for (id, tap) in taps where desired[id] != nil {
        if tap.callbackCount == 0,
           now().timeIntervalSince(tap.createdAt) > Self.healthWindow {
            stalled.append(id)
        }
    }
    for id in stalled {
        guard let tap = taps[id], let desiredTap = desired[id] else { continue }
        tap.stop()
        taps[id] = nil
        recordFailure(for: desiredTap, detail: "No audio is arriving.")
    }
}

private func recordFailure(for desiredTap: DesiredTap, detail: String) {
    let previousAttempts = failures[desiredTap.processObjectID]?.attempts ?? 0
    let attempts = previousAttempts + 1
    let index = min(attempts - 1, Self.retryDelays.count - 1)
    failures[desiredTap.processObjectID] = Failure(
        attempts: attempts,
        retryAt: now().addingTimeInterval(Self.retryDelays[index]),
        bundleID: desiredTap.bundleID,
        displayName: desiredTap.displayName,
        detail: detail
    )
}

private func recomputeHealth() {
    guard let failure = failures.values.min(by: { $0.retryAt < $1.retryAt }) else {
        health = .ok
        return
    }
    health = .stalled(
        displayName: failure.displayName,
        message: "\(failure.detail) Allow “Tapmix” in System Settings → Privacy & Security → Screen & System Audio Recording. Retrying automatically; press Retry to try now."
    )
}
```

Rules that are load-bearing:

- **Never call `stopAllTaps()` from health.** Only the stalled tap is stopped.
- `retry()` clears failure state without stopping healthy taps; the next `sync`
  creates the failed ones immediately because `failures` is empty.
- Backoff is per process object, attempts counted across start failures and stall
  events; the cap index is `retryDelays.count - 1`.
- A start error uses the error's localized description as `detail`; a stall uses
  `"No audio is arriving."`.
- The manager exposes `health` only; the engine must not keep its own failure map.

**Verify**: `swift build` → exit 0.

### Step 3: Rewire AudioEngine

Replace the tap state with:

```swift
private let tapManager = TapManager()
```

- `retry()`:
  ```swift
  public func retry() {
      tapManager.retry()
      errorMessage = nil
      refresh()
  }
  ```
- `setVolume` and `toggleMute`: replace `apply(level, to: bundleID)` with
  `tapManager.setGain(level.gain, for: bundleID)`.
- `shutdown()`: replace `stopAllTaps()` with `tapManager.stopAll()`.
- `reloadOutput()`: keep the no-output branch, but replace `stopAllTaps()` there
  with `tapManager.stopAll()`. Remove the `if outputUID != uid { ... stopAllTaps() }`
  block entirely; `refresh()` passes the new UID to `sync`, which rebuilds.
- `refresh()`:
  - Remove `playingObjects`, `checkHealth`, `shouldAttempt`, `failures` and
    `captureBlocked`.
  - Keep the process/group/row construction.
  - Replace `hasTaps` with `tapManager.activeBundleIDs.contains(bundleID)`.
  - For every group, call `tapManager.setGain(level.gain, for: bundleID)`.
  - Build `[TapManager.DesiredTap]` from processes where
    `process.isPlaying || tapManager.activeProcessIDs.contains(process.objectID)`.
    The second condition preserves the existing tap-through-pauses behavior; do
    not drop it.
  - After the loop:
    ```swift
    if let outputUID {
        tapManager.sync(desired: desired, outputUID: outputUID)
    } else {
        tapManager.stopAll()
    }
    ```
  - After assigning `apps`, map health to the banner:
    ```swift
    switch tapManager.health {
    case .ok:
        errorMessage = nil
    case let .stalled(_, message):
        errorMessage = message
    }
    ```
- Delete `apply`, `stopAllTaps`, `checkHealth`, `shouldAttempt`, `failures`,
  `captureBlocked`, and the `taps` dictionary. Keep `updateRow`.

**Verify**:
- `swift build` → exit 0.
- `grep -n "captureBlocked\|checkHealth\|shouldAttempt\|stopAllTaps\|failures" Sources/TapmixCore/AudioEngine.swift` → no output.

### Step 4: Add the fake and the tests

Create `Tests/TapmixTests/TapManagerTests.swift`. Use this test double:

```swift
final class FakeTap: TapControlling {
    let processObjectID: AudioObjectID
    let bundleID: String
    let createdAt: Date
    var callbackCount: UInt64 = 1
    var startError: Error?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var gain: Float = 1

    init(processObjectID: AudioObjectID, bundleID: String, createdAt: Date) {
        self.processObjectID = processObjectID
        self.bundleID = bundleID
        self.createdAt = createdAt
    }

    func start() throws {
        startCount += 1
        if let startError { throw startError }
    }
    func stop() { stopCount += 1 }
    func setGain(_ gain: Float) { self.gain = gain }
}
```

Use a `TestClock` (`var now: Date`) and a `Factory` class that records created
taps and output UIDs. Mark the test class `@MainActor` because `TapManager` is.

Tests to write (names are the contract):

1. `testSyncStartsOneTapPerDesiredProcess` — two desired taps → two starts, no
   duplicates on a second sync.
2. `testRemovedProcessIsStoppedAndCanReturn` — sync A, sync empty → stop once;
   sync A again → a new tap starts.
3. `testStalledTapStopsOnlyItself` — A and B start; advance the clock 7s; A has
   `callbackCount = 0`, B has `1`; sync → A.stopCount == 1, B.stopCount == 0,
   `health` is stalled for A, `activeProcessIDs` contains B.
4. `testNoStallBeforeWindow` — advance 5s, both zero callbacks; sync → no stops.
5. `testRetryClearsHealthAndRecreates` — after a stall, `retry()` → `.ok`; sync
   after the original 7s → a new A tap starts, B is not stopped.
6. `testStartFailureUsesBackoff` — factory/start throws; sync at t0 → stalled;
   sync at +14s → no second start; sync at +15s → second start.
7. `testOutputDeviceChangeRebuildsAll` — sync `"dev-1"`, then `"dev-2"` → old
   tap stops, new tap records `"dev-2"`.
8. `testGainAppliesToExistingAndNewTaps` — set 0.5, sync → 0.5; set 0 → existing
   tap 0; a later new tap starts at 0.
9. `testHealthyTapSurvivesAnotherStartFailure` — A throws at start, B starts;
   B.stopCount remains 0 and health names A.

**Verify**: `swift test --filter TapManagerTests` → 9 tests pass.

### Step 5: Full verification

- `swift test` → all tests pass.
- `swift build -c release` → exit 0.
- Manual: build and open the app; play audio in two apps; change one slider and
  confirm the other is unaffected. If a TCC prompt appears, take longer than 6s
  before allowing it; after allowing, press Retry and confirm only the stalled
  app is recreated (unit test 3/5 is the definitive check).

## Test plan

- New `TapManagerTests` (9 tests) is the primary regression suite. The key test
  is `testStalledTapStopsOnlyItself`; it fails against the old all-or-nothing
  behavior.
- No test touches Core Audio. `FakeTap` is the second adapter at the lifecycle
  seam.
- Existing `AudioMathTests` stay green.

## Done criteria

- [ ] `swift build` and `swift build -c release` exit 0.
- [ ] `swift test` exits 0; all 9 `TapManagerTests` pass.
- [ ] `grep -n "captureBlocked\|checkHealth\|shouldAttempt\|stopAllTaps\|failures" Sources/TapmixCore/AudioEngine.swift` returns nothing.
- [ ] `AudioEngine` stores no tap dictionary; `TapManager` is the only owner.
- [ ] `TapController` still has no `@MainActor` annotation and its render body is unchanged.
- [ ] Manual two-app test passes; a delayed TCC grant does not require a global Retry.
- [ ] No files outside the in-scope list are modified.

## STOP conditions

Stop and report if:

- Marking `TapManager` `@MainActor` produces an isolation error that cannot be
  solved without annotating `TapController` or its IO callback.
- The engine cannot preserve "existing tap survives a pause" without a new field
  on `DesiredTap`; do not silently change the behavior — report it.
- A manual test shows an app's audio stays muted after its tap is stopped (the
  `.mutedWhenTapped` contract did not restore); this is a Core Audio behavior
  problem, not a reason to add a workaround here.
- Any step requires modifying `TapController.render`; that belongs to plan 003.

## Maintenance notes

- Future routing/EQ work should extend `TapManager` (or add a new manager) rather
  than reintroducing lifecycle state in `AudioEngine`.
- The factory closure is the only place that constructs real `TapController`s.
  Tests and future fake devices use the other adapter.
- `healthWindow` (6s), `retryDelays` (15…300s) and the banner copy live only in
  `TapManager`; keep them there.
- If tap creation moves off the main actor later, `sync` becomes async; the fake
  seam already isolates tests from that change.
