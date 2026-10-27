# Architecture decisions — tap lifecycle, render plan, catalog

Recorded 2026-10-27 as the grilling output for the three candidates in the
architecture review. These are decisions, not suggestions: the plans execute
them. No source files were changed while writing this record.

## Shared constraints

- macOS 15+, Swift 6.4 toolchain, **Swift 5 language mode** (`swift-tools-version: 5.10`).
- SwiftPM only; no third-party dependencies, no private Apple APIs, no network.
- The realtime callback must not allocate, lock, log, or message Objective-C.
- Audio capture is TCC-gated; the app is launched with `open build/Tapmix.app`.
- The plans were written before the repository was initialized; their drift checks
  use SHA-256 hashes of the initial commit.
- The advisor may only write under `plans/`; hence no `GLOSSARY.md` or `docs/adr/`
  is created here. The "ADR candidates" below should be promoted once plans land.

## Candidate 1 — Tap lifecycle manager

### Decision

Create `TapManager` (`Sources/TapmixCore/TapManager.swift`) as the single owner
of tap lifecycle state. `AudioEngine` keeps polling, grouping and UI state only.

### Interface

```swift
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

    init(
        makeTap: @escaping (AudioObjectID, String, String) -> any TapControlling,
        now: @escaping () -> Date = Date.init
    )

    var health: Health { get }
    var activeProcessIDs: Set<AudioObjectID> { get }
    var activeBundleIDs: Set<String> { get }

    func setGain(_ gain: Float, for bundleID: String)
    func sync(desired: [DesiredTap], outputUID: String)
    func retry()
    func stopAll()
}
```

`TapControlling` is a small protocol (`processObjectID`, `bundleID`,
`createdAt`, `callbackCount`, `start() throws`, `stop()`, `setGain(_:)`).
`TapController` conforms; a `FakeTap` in tests is the second adapter. Two real
adapters justify the seam.

### State and policy

- One state machine inside the manager; the engine does not own `failures`,
  `captureBlocked` or `taps`.
- **Health is per tap.** A tap with zero callbacks after 6 seconds is stopped;
  every other tap keeps running. This is the fix for the observed global teardown.
- A failed tap gets exponential backoff: 15, 30, 60, 120, 300 seconds (cap).
- `Retry` clears failures and health; it does **not** stop healthy taps. The next
  `sync` recreates the failed ones.
- On output-device change, stop all taps and clear failures; rebuild with the new
  UID in the same `sync` call.
- Existing taps for processes that are no longer playing are preserved as long as
  the engine includes them in `desired` (the engine decides; see plan 002).
- The permission banner text lives in the manager's `Health` message; the engine
  only maps it to `errorMessage`.

### What stays out

- Discovery, filtering, helper resolution: plan 004.
- Realtime render and format handling: plan 003.
- Moving tap creation off the main actor: explicitly deferred. The manager's
  interface makes that later change local.

### Tests (the seam)

`Tests/TapmixTests/TapManagerTests.swift`, using `FakeTap`:
start once, gain propagation, removed process stop, **stalled tap stops only
itself**, retry recreates, backoff, output-device rebuild, start-error health,
and healthy taps surviving another tap's stall.

### ADR candidates

- "Tap lifecycle is owned by TapManager, not AudioEngine."
- "Health is per tap; a failed tap never tears down healthy taps."
- "Output-device changes rebuild all taps; no crossfade in v0.1."

## Candidate 2 — Explicit render plan

### Decision

Replace the implicit per-buffer render arithmetic with a small plan plus one
frame-major renderer. The tap is a stereo (or mono) stream and is the **last**
input buffer of the private aggregate; output channel 0 is left, 1 is right,
extra channels are zero.

### Interface

```swift
struct TapRenderPlan {
    let tapInputIndex: Int      // inputs.count - 1
    let tapInputChannels: Int   // 1 or 2
}

enum TapRender {
    static func writeFrame(
        left: Float, right: Float,
        into output: UnsafeMutablePointer<Float>,
        channels: Int, globalChannelOffset: Int,
        totalOutputChannels: Int, gain: Float
    )
    static func render(
        input: UnsafePointer<AudioBufferList>,
        output: UnsafeMutablePointer<AudioBufferList>,
        plan: TapRenderPlan,
        targetGain: Float,
        currentGain: inout Float,
        rampCoefficient: Float
    )
}
```

`AudioMath.process` is replaced by `TapRender`; `AudioMath.rampCoefficient` and
`clampedGain` remain. The four `AudioMath.process` tests move to
`TapRenderTests` with the same assertions plus planar/multichannel cases.

### Rules

- Gain advances **once per frame**, then every output buffer uses that gain. This
  fixes the shared-gain-per-buffer imbalance on planar outputs.
- A mono output mixes left+right; a mono tap is duplicated to both sides.
- A start-time format guard reads `kAudioTapPropertyFormat`; if the tap is not
  Float32 with ≤2 channels, throw a clear `TapError.unsupportedFormat`. If the
  format cannot be read, log and continue.
- If a live callback shows the tap is not the last input buffer, the renderer
  must zero output and log once; the plan must stop rather than guess.

### ADR candidates

- "One aggregate per process; the tap is the trailing input buffer."
- "Gain ramps are frame-major, not buffer-major."

## Candidate 3 — Pure audio catalog

### Decision

Extract discovery, helper resolution, filtering and row building into a pure
`AudioCatalog` over value snapshots. `AppResolver` becomes a pure function over
`RunningAppDescriptor` values. `AudioEngine` only adapts live data.

### Interface

```swift
struct RunningAppDescriptor {
    let pid: pid_t
    let bundleID: String?
    let name: String
    let icon: NSImage?
    let isRegular: Bool
    let isProhibited: Bool
    let bundlePath: String?
    let executablePath: String?
}

struct AppGroup {
    let bundleID: String
    let name: String
    let icon: NSImage?
    let isPlaying: Bool
    let processObjectIDs: [AudioObjectID]
    let playingProcessObjectIDs: [AudioObjectID]
    let level: AppLevel
}

enum AudioCatalog {
    static func groups(
        processes: [AudioProcess],
        running: [RunningAppDescriptor],
        levels: [String: AppLevel],
        activeBundleIDs: Set<String>
    ) -> [AppGroup]
}
```

### Preserved behaviour

- Only processes with a host `.app` are listed; daemons and orphan helpers are
  hidden.
- Helper processes group under the host app; the host supplies name and icon.
- A group is listed if it is playing, has a stored level, or has an active tap.
- The ignored bundle/name lists stay in `AppResolver` unchanged, including the
  local SoundSource/BGM entries; revisit before a public release.
- Sort by localized name.

### Tests

`Tests/TapmixTests/AudioCatalogTests.swift`: helper-to-host mapping, no-host
exclusion, ignored bundle, own bundle, playing group, stored-level idle group,
active-tap idle group, two helpers → one group, sort order.

### ADR candidates

- "Only host applications get a row; daemon audio is intentionally invisible."
- "Helper processes share the host's slider."

## Sequence

1. `001` output mute fallback + accessibility (independent, quick).
2. `002` TapManager (fixes health, creates the fake seam).
3. `003` render plan (builds on the TapManager-era `TapController`).
4. `004` catalog (uses `TapManager.activeProcessIDs`/`activeBundleIDs`).
5. `005` stable signing, check script, README/AGENTS.

## Open risks

- A tap can be silent while callbacks fire; the format guard catches formats, not
  wrong routing. The render tests and a manual stereo test are the mitigation.
- The tap-is-last assumption is verified indirectly (FineTune uses the same
  layout). Plan 003 includes a one-time diagnostic and a STOP condition.
- TCC prompts slower than 6 seconds now mark only that tap stalled and auto-retry;
  they no longer disable other apps.
