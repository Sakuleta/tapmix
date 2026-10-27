# Plan 001: Make output mute channel-complete and label the sliders

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the next
> step. If a STOP condition occurs, stop and report — do not improvise.
>
> **Drift check (run first)**: this repo was initialized after planning; compare the SHA-256
> hashes below with `shasum -a 256 <path>`; if a hash differs, compare the
> "Current state" excerpts with the live code. On a mismatch, STOP.
>
> `a5fd26a9275c2bf8bb70347cb7968801af1cc596d5eb931975df28247fa7560c  Sources/TapmixCore/AudioSystem.swift`
> `8c53d6f342d69cb97a17c24cd8ab65b1cd524c5fdfcb2a42c7bc409c23fed0c2  Sources/Tapmix/PanelView.swift`

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug + accessibility
- **Planned at**: pre-git snapshot, 2026-10-27
- **Issue**: not published

## Why this matters

On audio devices where the main-element HAL mute property is unsupported, the
mute fallback writes only output channel 1 and the reader only checks the main
element. The result is left-channel-only mute, and the panel flips back to
"unmuted" on the next poll. Separately, the two volume sliders have no
accessibility labels, so VoiceOver cannot say which app or device they control.
Both are small, user-visible correctness gaps.

## Current state

`Sources/TapmixCore/AudioSystem.swift:82-97`:

```swift
static func outputMuted(_ device: AudioObjectID) -> Bool? {
    guard let value: UInt32 = read(device, kAudioDevicePropertyMute, scope: scopeOutput) else {
        return nil
    }
    return value != 0
}

static func setOutputMuted(_ device: AudioObjectID, _ muted: Bool) {
    var address = propertyAddress(kAudioDevicePropertyMute, scope: scopeOutput)
    var value: UInt32 = muted ? 1 : 0
    let size = UInt32(MemoryLayout<UInt32>.size)
    if AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) != noErr {
        var channelAddress = propertyAddress(kAudioDevicePropertyMute, scope: scopeOutput, element: 1)
        _ = AudioObjectSetPropertyData(device, &channelAddress, 0, nil, size, &value)
    }
}
```

`AudioSystem.read` (`AudioSystem.swift:126-139`) currently takes a scope but no
element:

```swift
static func read<T>(
    _ objectID: AudioObjectID,
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = scopeGlobal
) -> T? { ... }
```

`Sources/Tapmix/PanelView.swift:93-102` (output slider) and `:247-255` (per-app
slider) have no `.accessibilityLabel`; the per-app mute button at `:235-245`
already has one. `AppRowView.icon` at `:268-282` and the playing dot at
`:219-221` are decorative.

Conventions to match: the file already uses `read(..., scope:)` wrappers and
private `readScalar`/`setScalar` helpers. Keep HAL code in `AudioSystem`; keep
SwiftUI modifiers on the view. Do not add protocols or new modules for this.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Build | `swift build` | exit 0 |
| Focused tests | `swift test --filter AudioSystemTests` | all pass |
| Full tests | `swift test` | all pass |
| Bundle (manual) | `./scripts/build-app.sh` | "Built build/Tapmix.app" |
| Run (manual) | `open build/Tapmix.app` | menu bar icon appears |

## Scope

**In scope** (the only files you should modify):
- `Sources/TapmixCore/AudioSystem.swift`
- `Sources/Tapmix/PanelView.swift`
- `Tests/TapmixTests/AudioSystemTests.swift` (create)

**Out of scope**:
- `AudioEngine`, `TapController`, `AudioMath`, `AppResolver`, `Models` — no
  behavior change belongs here.
- Output **volume** fallback logic; it already writes channels 1 and 2.
- Any change to the UI layout, colors, or panel height.

## Steps

### Step 1: Allow element-specific reads

In `AudioSystem.read<T>`, add an `element` parameter defaulting to `elementMain`
and pass it into `propertyAddress`:

```swift
static func read<T>(
    _ objectID: AudioObjectID,
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = scopeGlobal,
    element: AudioObjectPropertyElement = elementMain
) -> T? {
    var address = propertyAddress(selector, scope: scope, element: element)
    // ...existing body unchanged...
}
```

Existing call sites keep compiling because the parameter has a default.

**Verify**: `swift build` → exit 0.

### Step 2: Make mute read and write channel-complete

Add this internal helper next to the other mute functions (it is the unit-test
surface):

```swift
static func combinedMute(main: Bool?, channels: [Bool]) -> Bool? {
    if let main { return main }
    guard !channels.isEmpty else { return nil }
    return channels.allSatisfy { $0 }
}
```

Replace `outputMuted` with:

```swift
static func outputMuted(_ device: AudioObjectID) -> Bool? {
    let mainValue: UInt32? = read(device, kAudioDevicePropertyMute, scope: scopeOutput)
    let main = mainValue.map { $0 != 0 }
    var channels: [Bool] = []
    for channel: UInt32 in [1, 2] {
        if let value: UInt32 = read(
            device,
            kAudioDevicePropertyMute,
            scope: scopeOutput,
            element: channel
        ) {
            channels.append(value != 0)
        }
    }
    return combinedMute(main: main, channels: channels)
}
```

Replace the fallback in `setOutputMuted` with a loop over both channels:

```swift
static func setOutputMuted(_ device: AudioObjectID, _ muted: Bool) {
    var value: UInt32 = muted ? 1 : 0
    let size = UInt32(MemoryLayout<UInt32>.size)

    var mainAddress = propertyAddress(kAudioDevicePropertyMute, scope: scopeOutput)
    if AudioObjectSetPropertyData(device, &mainAddress, 0, nil, size, &value) == noErr {
        return
    }

    for channel: UInt32 in [1, 2] {
        var address = propertyAddress(
            kAudioDevicePropertyMute,
            scope: scopeOutput,
            element: channel
        )
        _ = AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
    }
}
```

**Verify**: `swift build` → exit 0.

### Step 3: Add the unit tests

Create `Tests/TapmixTests/AudioSystemTests.swift`:

```swift
import XCTest
@testable import TapmixCore

final class AudioSystemTests: XCTestCase {
    func testMainElementWinsWhenPresent() {
        XCTAssertEqual(AudioSystem.combinedMute(main: true, channels: [false, false]), true)
        XCTAssertEqual(AudioSystem.combinedMute(main: false, channels: [true, true]), false)
    }

    func testAllChannelsMuted() {
        XCTAssertEqual(AudioSystem.combinedMute(main: nil, channels: [true, true]), true)
    }

    func testPartialChannelMuteIsNotFullyMuted() {
        XCTAssertEqual(AudioSystem.combinedMute(main: nil, channels: [true, false]), false)
    }

    func testMonoChannelMute() {
        XCTAssertEqual(AudioSystem.combinedMute(main: nil, channels: [true]), true)
    }

    func testNoMuteProperty() {
        XCTAssertNil(AudioSystem.combinedMute(main: nil, channels: []))
    }
}
```

Do not add a test that touches real hardware; the CI/local test machine may not
have a mute-capable output.

**Verify**: `swift test --filter AudioSystemTests` → 5 tests pass.

### Step 4: Label the sliders and hide decorative icons

In `PanelView.outputSection`, add to the output `Slider` (after
`.controlSize(.small)`):

```swift
.accessibilityLabel("Output volume")
.accessibilityValue("\(Int((engine.outputVolume * 100).rounded())) percent")
```

In `AppRowView`, add to the per-app `Slider` (after `.tint(...)`):

```swift
.accessibilityLabel("Volume for \(app.name)")
.accessibilityValue("\(Int((app.volume * 100).rounded())) percent")
```

Add `.accessibilityHidden(true)` to the playing `Circle()` and to the `icon`
view (the app name is read separately). Do not hide the percentage text.

**Verify**:
- `swift build` → exit 0
- `grep -n "accessibilityLabel" Sources/Tapmix/PanelView.swift` → labels for
  output volume, output mute (already present), per-app mute, per-app volume.

## Test plan

- New `AudioSystemTests` covers the mute aggregation rule: main present, all
  channels muted, partial channel mute, mono, no property.
- Existing `AudioMathTests` remain untouched.
- Verification: `swift test` → all tests pass, including the 5 new ones.

## Done criteria

- [ ] `swift build` exits 0.
- [ ] `swift test` exits 0; 5 new `AudioSystemTests` pass.
- [ ] `grep -n "combinedMute" Sources/TapmixCore/AudioSystem.swift` returns the helper and both callers.
- [ ] `grep -n "accessibilityLabel" Sources/Tapmix/PanelView.swift` includes both sliders.
- [ ] No files outside the in-scope list changed (`shasum -a 256` the other source files and compare).
- [ ] Manual: with the built-in output, toggle output mute in the panel; the icon stays red and the next poll does not flip it back.

## STOP conditions

Stop and report if:

- `AudioObjectSetPropertyData` for elements 1 and 2 returns an error on the
  current output device **and** the main element also fails; the fix cannot be
  verified on hardware.
- The panel's slider labels compile but the volume binding stops working (the
  SwiftUI modifier changed the slider behavior).
- You need to change a file outside the scope to make the tests compile.

## Maintenance notes

- The rule considers channels 1 and 2 only. A >2-channel interface with
  per-channel mute needs the channel list extended; keep `combinedMute` as the
  single place for that policy.
- `combinedMute` treats a partially muted device as "not muted"; the next toggle
  writes both channels, which normalizes it.
- `AudioSystem` remains an internal static enum; tests use `@testable import`.
