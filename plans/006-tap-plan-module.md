# 006 — Tap plan module and recording ownership

**Status:** DONE
**Baseline:** 65e98a7 (0.2.4)
**Touches:** `Sources/TapmixCore/TapPlan.swift` (new), `AudioEngine.swift`,
`AudioSystem.swift`, `TapControlling.swift`, `TapController.swift`,
`TapManager.swift`, `Tests/TapmixTests/TapPlanTests.swift`,
`Tests/TapmixTests/TapManagerTests.swift`

## Goal

Give the “which process gets a tap, on which device” rule a name, a pure
interface and tests, and make the tap the only owner of recording state. This
also fixes two reported-class bugs:

1. A transient unreadable HAL process list used to look like “nothing is
   playing” and stopped every tap, producing a one-second dropout and a new
   aggregate device.
2. The red recording dot stayed on after the tap (and its recorder) had stopped.

## Current state (before)

`AudioEngine.refresh()` built `TapManager.DesiredTap` values inline, including
the route fallback and the playing/active filter. `AudioSystem.processes()`
returned `[]` both for “no process is using audio” and for “the HAL did not
answer”. `AudioEngine.recordingBundleIDs` was a second copy of a fact owned by
`TapController.recorder`, updated only by the UI's start/stop actions.

## Change

- `TapPlan.make(groups:availableUIDs:outputUID:activeProcessIDs:processListReadable:)`
  returns `TapPlan(taps:isComplete:)`. `isComplete == false` means the hardware
  did not answer; the engine keeps the live mix and skips row replacement.
- `AudioSystem.processes()` is now `[AudioProcess]?`, with `objectListOrNil`
  behind it. `objectList` keeps returning `[]` for callers that do not care.
- `TapControlling.isRecording` and `TapManager.recordingBundleIDs` derive the
  set from the recorders. `AudioEngine` publishes that set and deletes its copy.
- `stepActiveVolume` now applies `effectiveGain`, so a hotkey during a call no
  longer un-ducks the app for a second.

## Verification

- `swift test`: 132 tests pass, including 7 `TapPlanTests` and
  `testRecordingStateDiesWithTheTap`.
- `./scripts/check.sh`: OK.
- Manual: recorded a WAV, quit the player app, the row's recording dot cleared.

## Boundaries

- No change to `TapManager`'s lifecycle, backoff or health window.
- No change to route selection when the preferred route exists.
- `TapPlan` does not read the HAL and must not: inputs are passed in.

## Maintenance

- New tap policy (priority, per-app device groups) belongs in `TapPlan`, with a
  case in `TapPlanTests`; do not grow `refresh()` again.
- `isComplete` is the seam for any future “keep the mix on hardware hiccups”
  rule. If the HAL grows a cheaper validity check, thread it through here.
