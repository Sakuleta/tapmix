# 007 — Realtime handoff: atomics and teardown order

**Status:** DONE
**Baseline:** 4152bb6 (after 006)
**Touches:** `Sources/TapmixCore/EQProcessor.swift`, `TapRecorder.swift`,
`TapController.swift`, `AGENTS.md`

## Goal

Stop sharing mutable memory between the main thread and the render callback
without ordering, and stop freeing objects the render thread may still hold.
The previous code worked most of the time; the failures were a click when EQ
coefficients changed mid-copy and a race at tap teardown (quit, route change,
app close).

## Current state (before)

- `EQProcessor` kept one `coefficients` array written by `update()` on the main
  thread and copied into `active` by the render thread when a plain `Int32`
  revision differed. The source could be half-written during the copy, and the
  revision had no acquire/release pairing.
- `TapRecorder` used plain `Int` write/read indices across the render thread and
  a utility queue.
- `TapController.stop()` nil'd `audioUnitHost` and the recorder **before**
  `AudioDeviceStop`, so the last reference could be released on the audio thread
  (AU dispose, buffer free).

## Change

- **EQ banks**: three preallocated banks behind `Atomic<Int>`. The writer fills
  the bank after the published one and stores it with `.releasing`; the renderer
  loads with `.acquiring` and reads the bank in place. No copy, no allocation,
  no revision counter. Three banks keep the bank being written away from the two
  a callback can still hold.
- **Recorder ring**: `Atomic<Int>` indices; writer `.releasing` on the write
  index, drainer `.acquiring` it and `.releasing` the read index. The buffer
  walk in `write(bufferList:)` uses local indices and publishes once per call.
- **Teardown**: `stop()` stops and destroys the IO proc first, then releases the
  recorder and AU host on the tap queue (`queue.sync`). Recording install/removal
  also happens on that queue, so the callback never sees a half swap.
- `TapController.isRecording` is an atomic flag rather than a read of a
  queue-owned property.

## Verification

- `swift test`: 132/132, including the WAV round-trip and the recording-state
  tests from 006.
- `./scripts/check.sh`: OK.
- Manual: start/stop recording during playback; change EQ while playing; quit
  the player during a recording. No click, WAV header valid.

## Boundaries

- `TapRender` stays frame-major and allocation-free; no new locks anywhere in
  the callback.
- The peak level and `callbackCount` stay plain values (documented tradeoff:
  aligned 32/64-bit reads on Apple silicon, UI-only consumers).
- The EQ holds per-filter state across bank swaps on purpose, so changing a band
  does not reset the other filters' history.

## Maintenance

- Any new realtime value crossing threads must use `Synchronization.Atomic` and
  state its ordering; a plain property shared with the callback is a review
  blocker (AGENTS.md).
- If EQ updates ever exceed two per render callback (for example an automated
  sweep), add a fourth bank or a generation check before trusting the swap.
