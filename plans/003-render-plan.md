# Plan 003: Make the realtime render path explicit and testable

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If a
> STOP condition occurs, stop and report — do not improvise.
>
> **Drift check (run first)**: pre-git planning snapshot; compare the SHA-256 hashes below:
> `e35fee7c092a77c095c144c07a1624e0a398f289a4736a8fcb81f4cd19e0d23f  Sources/TapmixCore/TapController.swift`
> `6445944f0096d2defa8ffd32fa4cc3af398dd6c10a415fbe571815daccd90609  Sources/TapmixCore/AudioMath.swift`
> `893da1c3d5cfae35552ff3671d4dd2f4645f38a582a1dabb440ddd3f59d4ed4e  Tests/TapmixTests/AudioMathTests.swift`
> Plan 002 changes only the `TapController` class declaration (adds
> `: TapControlling`). Accept that one-line diff; stop on any other mismatch.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: HIGH
- **Depends on**: plans/002-tap-lifecycle-manager.md
- **Category**: bug + tech-debt
- **Planned at**: pre-git snapshot, 2026-10-27
- **Issue**: not published

## Why this matters

The HAL callback currently derives the tap's input buffer with
`inputs.count - outputs.count + outputIndex` and calls `AudioMath.process` once
per output buffer. Two implicit assumptions fail silently on some devices:

1. The tap is not necessarily at that index once hardware input streams or
   planar output buffers are involved.
2. The shared gain state advances once per output buffer, so a planar stereo
   output gets different left/right gains during a volume ramp.

Callbacks still fire when the audio is silent or imbalanced, so the health check
cannot catch it. This plan makes the mapping explicit, moves the gain ramp to
one step per frame across all output buffers, and adds a format guard so
unsupported tap formats fail at start instead of becoming silence.

Scope is the tap's render path only. The lifecycle manager (plan 002) and the
app catalog (plan 004) are separate.

## Current state

`TapController.render` (`TapController.swift:158-212`) is:

```swift
private func render(
    _ inputBufferList: UnsafePointer<AudioBufferList>,
    _ outputBufferList: UnsafeMutablePointer<AudioBufferList>
) {
    callbackCount &+= 1
    let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputBufferList))
    let outputs = UnsafeMutableAudioBufferListPointer(outputBufferList)
    guard !inputs.isEmpty, !outputs.isEmpty else { ... zero ...; return }

    let target = targetGain
    var gain = currentGain
    let coefficient = ramp

    for outputIndex in 0..<outputs.count {
        let outputBuffer = outputs[outputIndex]
        guard let outputData = outputBuffer.mData else { continue }
        let inputIndex = inputs.count - outputs.count + outputIndex
        guard inputIndex >= 0, inputIndex < inputs.count else { ... zero ...; continue }
        let inputBuffer = inputs[inputIndex]
        guard let inputData = inputBuffer.mData else { ... zero ...; continue }
        let inputChannels = max(1, Int(inputBuffer.mNumberChannels))
        let outputChannels = max(1, Int(outputBuffer.mNumberChannels))
        let inputFrames = Int(inputBuffer.mDataByteSize) / (MemoryLayout<Float>.size * inputChannels)
        let outputFrames = Int(outputBuffer.mDataByteSize) / (MemoryLayout<Float>.size * outputChannels)
        AudioMath.process(
            input: inputData.assumingMemoryBound(to: Float.self),
            inputChannels: inputChannels,
            inputFrames: inputFrames,
            output: outputData.assumingMemoryBound(to: Float.self),
            outputChannels: outputChannels,
            outputFrames: outputFrames,
            targetGain: target,
            currentGain: &gain,
            rampCoefficient: coefficient
        )
    }
    currentGain = gain
}
```

`AudioMath.process` (`AudioMath.swift:20-75`) zeroes one output buffer, loops its
frames, advances the gain per frame, and copies/clamps channels. Its four tests
live in `Tests/TapmixTests/AudioMathTests.swift:5-102`.

`TapController.start()` creates the tap at `:61-71`, the aggregate at `:73-94`,
reads the sample rate at `:96-97` and starts the IO proc at `:98-121`.

Fact to rely on: a private aggregate appends the tap stream after the output
device's input streams, so the **tap is the last input buffer**. This is the
same layout FineTune relies on. The plan guards it with a start-time format check
and a STOP condition.

Conventions: realtime code must not allocate, lock, log, or call Objective-C.
`TapError` is the existing error type in `TapController.swift:6-15`.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `swift build` | exit 0 |
| Focused tests | `swift test --filter TapRenderTests` | all pass |
| Full tests | `swift test` | all pass |
| Manual run | `./scripts/build-app.sh && open build/Tapmix.app` | stereo playback works |

## Scope

**In scope**:
- `Sources/TapmixCore/TapRender.swift` (create)
- `Sources/TapmixCore/TapController.swift` (render + start guard)
- `Sources/TapmixCore/AudioMath.swift` (delete `process`, keep `rampCoefficient`/`clampedGain`)
- `Tests/TapmixTests/TapRenderTests.swift` (create)
- `Tests/TapmixTests/AudioMathTests.swift` (remove the moved process tests)

**Out of scope**:
- `TapManager`, `AudioEngine`, `AppResolver`, `Models`, `PanelView`.
- EQ, limiter, routing, multichannel support beyond "extra output channels are
  zero"; those are later product work.
- Changing the aggregate description or the tap's mute behavior.

## Steps

### Step 1: Add TapRenderPlan and TapRender

Create `Sources/TapmixCore/TapRender.swift` with exactly this behavior:

```swift
import AudioToolbox
import CoreAudio
import Foundation

struct TapRenderPlan: Equatable {
    let tapInputIndex: Int
    let tapInputChannels: Int

    static func make(inputBufferCount: Int, tapInputChannels: Int) -> TapRenderPlan? {
        guard inputBufferCount > 0, (1...2).contains(tapInputChannels) else { return nil }
        return TapRenderPlan(
            tapInputIndex: inputBufferCount - 1,
            tapInputChannels: tapInputChannels
        )
    }
}

enum TapRender {
    static func render(
        input: UnsafePointer<AudioBufferList>,
        output: UnsafeMutablePointer<AudioBufferList>,
        plan: TapRenderPlan,
        targetGain: Float,
        currentGain: inout Float,
        rampCoefficient: Float
    ) { ... }

    @inline(__always)
    static func writeFrame(
        left: Float,
        right: Float,
        into output: UnsafeMutablePointer<Float>,
        channels: Int,
        globalChannelOffset: Int,
        totalOutputChannels: Int,
        gain: Float
    ) { ... }
}
```

Implementation rules:

1. Zero every output buffer first (`memset`) so a short tap cannot leak stale
   hardware audio.
2. Read `inputs[plan.tapInputIndex]`; if missing or `mData == nil`, return after
   zeroing.
3. `tapChannels = max(1, min(plan.tapInputChannels, 2))`.
4. `frames` is the minimum of the tap frames and every output buffer's frames
   (compute by dividing byte size by `Float` size × channel count).
5. Loop **frames on the outside**. Advance `gain` once per frame:
   `gain += (goal - gain) * coefficient`, with
   `goal = AudioMath.clampedGain(targetGain)` and
   `coefficient = min(max(rampCoefficient, 0), 1)`.
6. Read `left` and `right` from the tap frame (`right = left` for mono).
7. Loop output buffers on the inside, tracking `globalChannelOffset` across
   buffers; call `writeFrame` for each buffer at
   `data.advanced(by: frame * channels)`.
8. Save `currentGain = gain` at the end.

`writeFrame` rules:

- If `totalOutputChannels == 1`: write
  `clamp(((left + right) * 0.5) * gain)` to channel 0.
- Otherwise global channel 0 gets `left`, global channel 1 gets `right`, and all
  other global channels get 0 (all multiplied by gain and clamped to ±1).
- Clamp is a private `min(max(sample, -1), 1)`.

Add the total output channel count by summing
`max(1, Int($0.mNumberChannels))` over the output buffers **before** the frame
loop.

**Verify**: `swift build` → exit 0. No `Array` creation inside `render`.

### Step 2: Replace TapController.render

Keep `callbackCount &+= 1`. Replace the body with:

```swift
let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputBufferList))
guard let tapBuffer = inputs.last,
      let plan = TapRenderPlan.make(
          inputBufferCount: inputs.count,
          tapInputChannels: Int(tapBuffer.mNumberChannels)
      )
else {
    TapController.zero(outputBufferList)
    return
}

TapRender.render(
    input: inputBufferList,
    output: outputBufferList,
    plan: plan,
    targetGain: targetGain,
    currentGain: &currentGain,
    rampCoefficient: ramp
)
```

Do not call `AudioMath.process` anywhere.

**Verify**: `grep -rn "AudioMath.process" Sources Tests` → no matches (after
step 3 removes its tests).

### Step 3: Remove the old process routine and move its tests

In `AudioMath.swift`, delete `process` and the private `clamp`; keep
`rampSeconds`, `rampCoefficient` and `clampedGain`.

In `Tests/TapmixTests/AudioMathTests.swift`, delete the four tests that call
`AudioMath.process` (`testStereoCopyAtUnityGain`, `testMonoIsDuplicatedToStereo`,
`testBoostClampsAndFillsTailWithSilence`, `testMutedGainRampsToSilence`). Keep
`testLevelStoreRoundTrip` (it uses only `LevelStore`/`AppLevel`).

**Verify**: `swift test` → the remaining tests build and pass.

### Step 4: Add a start-time tap format guard

Add a case to `TapError`:

```swift
case unsupportedFormat(String)
```

and an error description such as
`"The tap format is not supported: \(detail)"`.

Add this helper to `TapController`:

```swift
private func processTapFormat(_ tapID: AudioObjectID) -> AudioStreamBasicDescription? {
    var address = AudioSystem.propertyAddress(kAudioTapPropertyFormat)
    var format = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    guard AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format) == noErr else {
        return nil
    }
    return format
}
```

In `start()`, immediately after the tap is created (`:68-71`), before creating
the aggregate:

```swift
if let format = processTapFormat(newTapID) {
    let supported = format.mFormatID == kAudioFormatLinearPCM
        && (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        && (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
        && format.mBitsPerChannel == 32
        && format.mChannelsPerFrame <= 2
    guard supported else {
        AudioHardwareDestroyProcessTap(newTapID)
        throw TapError.unsupportedFormat(
            "id=\(format.mFormatID) flags=\(format.mFormatFlags) bits=\(format.mBitsPerChannel) channels=\(format.mChannelsPerFrame)"
        )
    }
} else {
    log.warning("Could not read the tap format; assuming interleaved Float32.")
}
```

Do not log from `render`; this guard runs on the setup path. The existing start
log may include the stream counts; keep it.

**Verify**: `swift build` → exit 0.

### Step 5: Write TapRenderTests

Create `Tests/TapmixTests/TapRenderTests.swift`. At minimum:

1. `testWriteFrameStereo` — global 0/1 get left/right, gain 1.
2. `testWriteFrameMonoOutputIsMixdown` — `totalOutputChannels = 1` gets
   `(left+right)/2`.
3. `testWriteFrameExtraChannelsAreZero` — 4-channel output: 0/1 set, 2/3 zero.
4. `testWriteFrameGlobalOffset` — a 2-channel buffer at offset 2 writes zero to
   both channels.
5. `testClampAtUnity` — left 0.8/right -0.9 at gain 2 → 1.0/-1.0.
6. `testRenderStereoInterleaved` — one input buffer (2 channels) and one output
   buffer (2 channels); gain target 1, ramp coefficient 1 → exact copy.
7. `testRenderPlanarOutputUsesOneRamp` — input 1×2ch, output 2×1ch; target 2,
   ramp coefficient 0.5; assert both output buffers at frame 0 receive the same
   gain, and left/right stay aligned across frames. This is the regression for
   the per-buffer ramp bug.
8. `testRenderMuteWritesSilence` — target 0, ramp 1 → zeros.

Use this helper to build and inspect buffer lists (it allocates by hand and frees
in `deinit`):

```swift
final class TestBufferList {
    let list: UnsafeMutableAudioBufferListPointer
    private var storage: [UnsafeMutableRawPointer] = []

    init(channels: [Int], frames: Int) {
        list = AudioBufferList.allocate(maximumBuffers: channels.count)
        for (index, channelCount) in channels.enumerated() {
            let byteCount = frames * channelCount * MemoryLayout<Float>.size
            let data = UnsafeMutableRawPointer.allocate(
                byteCount: byteCount,
                alignment: MemoryLayout<Float>.alignment
            )
            memset(data, 0, byteCount)
            storage.append(data)
            list[index] = AudioBuffer(
                mNumberChannels: UInt32(channelCount),
                mDataByteSize: UInt32(byteCount),
                mData: data
            )
        }
    }

    func write(_ samples: [Float], at index: Int) {
        let buffer = list[index]
        guard let destination = buffer.mData else { return }
        samples.withUnsafeBytes { bytes in
            memcpy(destination, bytes.baseAddress, bytes.count)
        }
    }

    func read(at index: Int) -> [Float] {
        let buffer = list[index]
        guard let data = buffer.mData else { return [] }
        let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        return Array(UnsafeBufferPointer(
            start: data.assumingMemoryBound(to: Float.self),
            count: count
        ))
    }

    deinit {
        for data in storage { data.deallocate() }
        free(list.unsafeMutablePointer)
    }
}
```

If `AudioBufferList.allocate` behaves differently than described, stop and report
rather than leaking or freeing stack memory. Do not weaken the planar test:
the planar case is the reason this plan exists.

Example single-buffer render test shape:

```swift
var input: [Float] = [0.5, -0.5, 0.25, 0]
var output: [Float] = [0, 0, 0, 0]
var gain: Float = 0

input.withUnsafeMutableBytes { inputBytes in
    output.withUnsafeMutableBytes { outputBytes in
        var inBuffer = AudioBuffer(
            mNumberChannels: 2,
            mDataByteSize: UInt32(inputBytes.count),
            mData: inputBytes.baseAddress
        )
        var outBuffer = AudioBuffer(
            mNumberChannels: 2,
            mDataByteSize: UInt32(outputBytes.count),
            mData: outputBytes.baseAddress
        )
        var inList = AudioBufferList(mNumberBuffers: 1, mBuffers: inBuffer)
        var outList = AudioBufferList(mNumberBuffers: 1, mBuffers: outBuffer)
        withUnsafePointer(to: &inList) { inPointer in
            withUnsafeMutablePointer(to: &outList) { outPointer in
                TapRender.render(
                    input: inPointer,
                    output: outPointer,
                    plan: TapRenderPlan(tapInputIndex: 0, tapInputChannels: 2),
                    targetGain: 1,
                    currentGain: &gain,
                    rampCoefficient: 1
                )
            }
        }
    }
}

XCTAssertEqual(output, [0.5, -0.5, 0.25, 0])
```

**Verify**: `swift test --filter TapRenderTests` → all pass.

## Test plan

- New tests cover channel mapping, mono mixdown, extra channels, clamping, the
  interleaved copy, the planar one-ramp regression, and mute.
- Existing `AudioMathTests.testLevelStoreRoundTrip` stays.
- No test touches Core Audio; `TapRender` is a pure function over buffer lists.

## Done criteria

- [ ] `swift build` and `swift build -c release` exit 0.
- [ ] `swift test` exits 0; `TapRenderTests` has at least 8 passing tests.
- [ ] `grep -rn "AudioMath.process" Sources Tests` returns nothing.
- [ ] `grep -n "inputIndex = inputs.count" Sources/TapmixCore/TapController.swift` returns nothing.
- [ ] `TapRender.render` advances the gain exactly once per frame (visible in the code and covered by the planar test).
- [ ] `TapController.start` throws on a non-interleaved / non-Float32 / >2-channel tap.
- [ ] Manual stereo test: play a stereo track on the built-in output, move the app slider from 100% to 30% and back; both channels stay centered and the volume ramps smoothly.
- [ ] No files outside the in-scope list changed.

## STOP conditions

Stop and report if:

- `kAudioTapPropertyFormat` returns a format that the guard rejects for a normal
  stereo process tap on the built-in output (report the exact fields).
- A live manual test shows the tap is not the last input buffer (e.g. the start
  log shows unexpected stream counts and playback is silent). Do not guess a new
  index; this needs a real buffer-layout probe.
- The planar AudioBufferList test cannot be built without weakening the
  assertion; report the blocker instead of removing the regression test.
- The change requires touching `TapManager` or `AudioEngine` beyond the plan.

## Maintenance notes

- The renderer assumes a stereo (or mono) **interleaved** tap. That is what a
  `stereoMixdownOfProcesses` tap produces; the format guard enforces it.
- One aggregate contains one tap. If multi-tap aggregates are added later, the
  "last input buffer" assumption and `TapRenderPlan` must be revisited.
- Output channels beyond left/right are deliberately zero. Surround support is
  a product decision, not a bug in this plan.
- Keep the RT callback allocation-free: no arrays, no logging, no locks.
