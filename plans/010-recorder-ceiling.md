# 010 — Recorder survives a full disk and the 4 GB header

**Status:** DONE
**Baseline:** 69a1437 (after 008)
**Touches:** `Sources/TapmixCore/TapRecorder.swift`,
`Tests/TapmixTests/TapRecorderTests.swift`, `README.md`

## Goal

Two failure modes of a long recording:

1. `FileHandle.write(_:)` raises an Objective-C exception when the write fails
   (a full disk or a removed volume), taking the app down mid-recording.
2. The WAV data chunk is a 32-bit byte count. At 48 kHz stereo 16-bit the file
   passes 4 GB after about 6.2 hours; the header then wraps and the file is
   unreadable.

## Current state (before)

`drain()` accumulated frames in a `Data`, called `fileHandle.write(data)` (the
raising variant) and added `data.count / 4` to a `UInt32`. Nothing capped the
count and nothing handled a write error.

## Change

- `drain()` uses `try fileHandle.write(contentsOf:)`; on failure it closes the
  file cleanly with the frames already written.
- `TapRecorder(maxFrames:)` (internal, default `UInt32.max / 4`) caps the data
  chunk. When reached, the recorder finalises the header and closes; the ring
  stops accepting new frames because `active` turns false.
- `finish()` closes exactly once, from the recorder queue; `stop()` funnels
  through it, so a second stop is a no-op on a closed handle.
- README's recording section documents the 4 GB ceiling and the full-disk
  behaviour.

## Verification

- `swift test --filter TapRecorderTests`: 4 tests, including
  `testStopsAtTheFrameCeiling` (2,000 frames written, 1,000 kept, header says
  4,000 bytes) and `testSecondStopIsANoOp`.
- `./scripts/check.sh`: OK.
- Manual: record a few seconds, stop, reopen the file; the header matches.

## Boundaries

- One file per tap stays; no splitting into multiple WAVs or RF64. A future
  “record longer than 6 hours” feature needs RF64/BW64, which is a format
  change, not a header patch.
- The ring buffer and its atomics from 007 are unchanged.
- No UI for the remaining time; the stop happens silently, as before.

## Maintenance

- If RF64 is added, the ceiling parameter becomes a format choice; keep the
  header writer in one place (`TapRecorder.header`/`patchHeader`).
- Any new file write in the recorder queue must use the throwing API and end
  through `finish()`.
