# Plan 004: Extract a pure audio catalog and test helper resolution

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If a
> STOP condition occurs, stop and report — do not improvise.
>
> **Drift check (run first)**: pre-git planning snapshot; compare the SHA-256 hashes below:
> `5233526383d7ccebfb31ece6de4a3ff1e43c5fc6821704dc897254385bbb80c2  Sources/TapmixCore/AudioEngine.swift`
> `21439b6e829009686dbabfe5885d30f67c2558b2b0ed14e307697e8ff3689419  Sources/TapmixCore/AppResolver.swift`
> `c5f747635c1ea8208f794728977198fc6d8bfab313bbef98d8500d0eb40d5ab7  Sources/TapmixCore/Models.swift`
> Plan 002 changes `AudioEngine.swift` substantially; accept that diff and
> compare the post-002 shape described below. Stop if `AudioEngine` still has
> `captureBlocked`/`checkHealth` — plan 002 has not landed.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW-MED
- **Depends on**: plans/002-tap-lifecycle-manager.md
- **Category**: tech-debt + tests
- **Planned at**: pre-git snapshot, 2026-10-27
- **Issue**: not published

## Why this matters

`AudioEngine.refresh()` is the only place that knows which processes become
rows, how helper processes map to a host app, which ignored bundles are hidden,
and when an idle app stays visible. It performs all of that inside a
`@MainActor` HAL poll loop and reads `NSRunningApplication` directly, so none of
the policy is testable: `AudioEngine` and `AppResolver` are both at 0% line
coverage. Every product change (pinning, ignore lists, routing) will add another
branch to the same method.

This plan turns the live inputs into a value snapshot and moves the policy into a
pure `AudioCatalog`. Behaviour is preserved exactly; the output is the same
`AppRow` list plus the per-bundle process IDs needed for tap selection.

## Current state

`AudioEngine.refresh` currently builds `groups` and `identities` itself
(`AudioEngine.swift:134-209` before plan 002):

```swift
let running = NSWorkspace.shared.runningApplications
var groups: [String: [AudioProcess]] = [:]
var identities: [String: AppIdentity] = [:]

for process in processes {
    guard let identity = AppResolver.resolve(process, running: running) else { continue }
    groups[identity.bundleID, default: []].append(process)
    identities[identity.bundleID] = identity
}
```

`AppResolver.resolve` (`AppResolver.swift:56-99`) reads
`NSRunningApplication(processIdentifier:)` and scans
`NSWorkspace.shared.runningApplications`, then applies the helper-path and
ignored-prefix rules. The ignored lists are at `:13-54`; the helper-to-host
walk is at `:71-79`.

`Models.swift:19-49` has `LevelStore` with `level(for:)` and `hasLevel(for:)`,
but no way to read all levels for the catalog.

After plan 002, `AudioEngine` owns a `TapManager` with:

```swift
var activeProcessIDs: Set<AudioObjectID> { get }
var activeBundleIDs: Set<String> { get }
```

and a `sync(desired: [TapManager.DesiredTap], outputUID: String)`. The catalog
must feed that desired list.

Behaviour to preserve:
- Only processes whose host is a real `.app` are listed; daemons/orphan helpers
  are hidden.
- Helper processes merge under the host app; host name and icon win.
- A group is listed if playing, a stored level exists, or an active tap exists.
- Rows sort by localized name.
- `Bundle.main.bundleIdentifier` and `com.sakuleta.tapmix` are excluded.
- The local SoundSource/BGM ignored prefixes remain for now.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `swift build` | exit 0 |
| Focused tests | `swift test --filter AudioCatalogTests` | all pass |
| Full tests | `swift test` | all pass |
| Manual run | `./scripts/build-app.sh && open build/Tapmix.app` | Brave/Chrome helper under its host |

## Scope

**In scope**:
- `Sources/TapmixCore/RunningAppDescriptor.swift` (create)
- `Sources/TapmixCore/AudioCatalog.swift` (create)
- `Sources/TapmixCore/AppResolver.swift`
- `Sources/TapmixCore/AudioEngine.swift`
- `Sources/TapmixCore/Models.swift` (add `allLevels`)
- `Tests/TapmixTests/AudioCatalogTests.swift` (create)

**Out of scope**:
- `TapManager` internals (it already exposes active IDs from plan 002).
- `TapController`, `TapRender`, `AudioMath`.
- Changing the ignored bundle list or the visual design.
- Adding pinning/ignore/search — those are later product work; this plan only
  makes the current policy testable.

## Steps

### Step 1: Add the running-app value snapshot

Create `Sources/TapmixCore/RunningAppDescriptor.swift`:

```swift
import AppKit
import Foundation

struct RunningAppDescriptor {
    let pid: pid_t
    let bundleID: String?
    let name: String
    let icon: NSImage?
    let isRegular: Bool
    let isProhibited: Bool
    let bundlePath: String?
    let executablePath: String?

    static func snapshot(_ apps: [NSRunningApplication]) -> [RunningAppDescriptor] {
        apps.map { app in
            RunningAppDescriptor(
                pid: app.processIdentifier,
                bundleID: app.bundleIdentifier,
                name: app.localizedName ?? app.bundleIdentifier ?? "Unknown",
                icon: app.icon,
                isRegular: app.activationPolicy == .regular,
                isProhibited: app.activationPolicy == .prohibited,
                bundlePath: app.bundleURL?.resolvingSymlinksInPath().path,
                executablePath: app.executableURL?.resolvingSymlinksInPath().path
            )
        }
    }
}
```

Do not add `Hashable` (NSImage is not hashable); the catalog only iterates.

**Verify**: `swift build` → exit 0.

### Step 2: Make AppResolver pure

Change the signature to accept descriptors:

```swift
static func resolve(
    _ process: AudioProcess,
    running: [RunningAppDescriptor]
) -> AppIdentity?
```

Replace the two `NSRunningApplication` lookups with descriptor lookups:

```swift
let direct = running.first { $0.pid == process.pid }
var host: RunningAppDescriptor?

if let direct, direct.isRegular, direct.bundlePath?.hasSuffix(".app") == true {
    host = direct
}

if host == nil, let executable = direct?.executablePath {
    host = running.first { app in
        guard !app.isProhibited, let path = app.bundlePath else { return false }
        return executable == path || executable.hasPrefix(path + "/")
    }
}

guard let host, let bundleID = host.bundleID else { return nil }
let name = host.name.isEmpty
    ? (bundleID.split(separator: ".").last.map(String.init) ?? bundleID)
    : host.name
guard !bundleID.isEmpty, !isIgnored(bundleID: bundleID, name: name) else { return nil }
let icon = host.icon ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)
return AppIdentity(bundleID: bundleID, name: name, icon: icon)
```

Keep the own-bundle check and the ignored lists unchanged. Delete the old
`NSRunningApplication(processIdentifier:)` code and the `direct?.localizedName`
fallback; the descriptor's `name` replaces it.

**Verify**: `swift build` → exit 0.

### Step 3: Add the catalog

Create `Sources/TapmixCore/AudioCatalog.swift`:

```swift
import AppKit
import CoreAudio
import Foundation

struct AppGroup {
    let bundleID: String
    let name: String
    let icon: NSImage?
    let isPlaying: Bool
    let processObjectIDs: [AudioObjectID]
    let playingProcessObjectIDs: [AudioObjectID]
    let level: AppLevel

    var row: AppRow {
        AppRow(
            bundleID: bundleID,
            name: name,
            icon: icon,
            isPlaying: isPlaying,
            volume: level.volume,
            muted: level.muted
        )
    }
}

enum AudioCatalog {
    static func groups(
        processes: [AudioProcess],
        running: [RunningAppDescriptor],
        levels: [String: AppLevel],
        activeBundleIDs: Set<String>
    ) -> [AppGroup] {
        var grouped: [String: [AudioProcess]] = [:]
        var identities: [String: AppIdentity] = [:]

        for process in processes where !process.bundleID.isEmpty {
            guard let identity = AppResolver.resolve(process, running: running) else { continue }
            grouped[identity.bundleID, default: []].append(process)
            identities[identity.bundleID] = identity
        }

        return grouped.compactMap { bundleID, bundleProcesses in
            guard let identity = identities[bundleID] else { return nil }
            let playing = bundleProcesses.contains { $0.isPlaying }
            guard playing || levels[bundleID] != nil || activeBundleIDs.contains(bundleID) else {
                return nil
            }
            return AppGroup(
                bundleID: bundleID,
                name: identity.name,
                icon: identity.icon,
                isPlaying: playing,
                processObjectIDs: bundleProcesses.map(\.objectID),
                playingProcessObjectIDs: bundleProcesses.filter(\.isPlaying).map(\.objectID),
                level: levels[bundleID] ?? AppLevel()
            )
        }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
```

**Verify**: `swift build` → exit 0.

### Step 4: Expose levels and rewire AudioEngine

Add to `LevelStore`:

```swift
public var allLevels: [String: AppLevel] { levels }
```

Replace the discovery part of `AudioEngine.refresh` with:

```swift
let processes = AudioSystem.processes()
let running = RunningAppDescriptor.snapshot(NSWorkspace.shared.runningApplications)
let groups = AudioCatalog.groups(
    processes: processes,
    running: running,
    levels: store.allLevels,
    activeBundleIDs: tapManager.activeBundleIDs
)

for group in groups {
    tapManager.setGain(group.level.gain, for: group.bundleID)
}

var desired: [TapManager.DesiredTap] = []
for group in groups {
    for processID in group.processObjectIDs
    where group.playingProcessObjectIDs.contains(processID)
        || tapManager.activeProcessIDs.contains(processID)
    {
        desired.append(
            TapManager.DesiredTap(
                processObjectID: processID,
                bundleID: group.bundleID,
                displayName: group.name
            )
        )
    }
}

if let outputUID {
    tapManager.sync(desired: desired, outputUID: outputUID)
} else {
    tapManager.stopAll()
}

apps = groups.map(\.row)
switch tapManager.health {
case .ok:
    errorMessage = nil
case let .stalled(_, message):
    errorMessage = message
}
```

Remove the old `groups`/`identities` dictionaries, the `AppResolver.resolve`
loop, the per-group row construction and the `playingObjects` set. Keep the
`reloadOutput` polling and the `setVolume`/`toggleMute`/`updateRow` methods
unchanged. `NSWorkspace` now appears only in the one `snapshot` call.

**Verify**:
- `swift build` → exit 0.
- `grep -n "AppResolver" Sources/TapmixCore/AudioEngine.swift` → no output.
- `grep -n "NSWorkspace" Sources/TapmixCore/AudioEngine.swift` → exactly one line.

### Step 5: Add catalog tests

Create `Tests/TapmixTests/AudioCatalogTests.swift`. Use fake descriptors and
`AudioProcess` values; icons are nil.

Descriptors:

```swift
let braveHost = RunningAppDescriptor(
    pid: 5, bundleID: "com.brave.Browser", name: "Brave Browser", icon: nil,
    isRegular: true, isProhibited: false,
    bundlePath: "/Applications/Brave Browser.app",
    executablePath: "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
)
let braveHelper = RunningAppDescriptor(
    pid: 10, bundleID: "com.brave.Browser.helper", name: "Brave Helper", icon: nil,
    isRegular: false, isProhibited: true,
    bundlePath: "/Applications/Brave Browser.app/Contents/Frameworks/Brave Helper.app",
    executablePath: "/Applications/Brave Browser.app/Contents/Frameworks/Brave Helper.app/Contents/MacOS/Brave Helper"
)
```

Process: `AudioProcess(objectID: 1, pid: 10, bundleID: "com.brave.Browser.helper", isPlaying: true)`.

Tests:

1. `testHelperMapsToHost` — expect one group `Brave Browser`, ID `com.brave.Browser`, playing IDs `[1]`.
2. `testOrphanHelperIsHidden` — only the helper descriptor, no host → empty.
3. `testIgnoredBundleIsHidden` — host `com.apple.coreaudio` → empty.
4. `testOwnBundleIsHidden` — `com.sakuleta.tapmix` → empty.
5. `testPlayingAppAppearsWithoutStoredLevel`.
6. `testStoredLevelKeepsIdleApp` — process `isPlaying: false`, level `[id: AppLevel(volume: 0.4)]` → one group, `isPlaying` false.
7. `testActiveTapKeepsIdleApp` — `activeBundleIDs: [id]` → one group.
8. `testTwoHelpersMergeUnderHost` — two processes (IDs 1,2) same host → one group, `processObjectIDs == [1,2]` (sort if needed), `playingProcessObjectIDs` includes both.
9. `testRowsSortByLocalizedName` — two hosts "Zebra"/"Alpha" → Alpha first.
10. `testIdleAppWithoutLevelOrTapIsHidden` — empty.

Use `@testable import TapmixCore`. No Core Audio calls.

**Verify**: `swift test --filter AudioCatalogTests` → 10 tests pass.

## Test plan

- The catalog tests are pure and hardware-free. The helper-to-host case is the
  one that used to require a live browser.
- Existing `TapManagerTests` (plan 002) and `TapRenderTests` (plan 003) stay green.
- Manual regression: open Brave (or Chrome) with a YouTube tab; the panel must
  show one host row, not a "helper" row.

## Done criteria

- [ ] `swift build` and `swift test` exit 0; all 10 `AudioCatalogTests` pass.
- [ ] `AudioEngine.refresh` contains no `AppResolver.resolve`, ignored lists,
  `groups`/`identities` dictionaries, or row construction.
- [ ] `NSWorkspace` appears exactly once in `Sources/TapmixCore/AudioEngine.swift`.
- [ ] `RunningAppDescriptor.snapshot` is the only adapter that reads
  `NSRunningApplication` properties.
- [ ] Manual helper mapping is unchanged (Brave/Chrome shows the host name).
- [ ] No files outside the in-scope list changed.

## STOP conditions

Stop and report if:

- A real browser's helper cannot be resolved through the descriptor snapshot
  (e.g. `NSWorkspace.shared.runningApplications` does not include the helper).
  Do not add a second `NSRunningApplication` lookup inside `AppResolver`.
- The catalog changes the visible app list in a way not explained by the tests
  (e.g. an app that used to show disappears).
- `NSImage` in `AppGroup` forces `Equatable`/`Hashable` changes across models.
  Tests should pass `nil` icons; do not refactor the model for this plan.
- A required descriptor field is missing (e.g. activation policy granularity);
  report the missing fact instead of guessing.

## Maintenance notes

- This is the seam for future pinning/ignore/search: add fields to the snapshot
  or catalog inputs, not branches in `AudioEngine`.
- `AppResolver` remains the single place for host resolution and ignored
  prefixes; the local SoundSource/BGM entries are deliberate for now.
- If a future feature needs the process's host for reasons other than display
  (e.g. routing), reuse `AppIdentity` instead of re-deriving it.
- Keep the catalog pure: no `NSWorkspace`, no HAL, no timers.
