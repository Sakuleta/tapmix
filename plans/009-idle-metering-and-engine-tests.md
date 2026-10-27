# 009 — Idle metering and engine action tests

**Status:** DONE
**Baseline:** 4152bb6 (after 006)
**Touches:** `Sources/TapmixCore/AudioEngine.swift`,
`RunningAppDescriptor.swift`, `Sources/Tapmix/PanelView.swift`,
`Tests/TapmixTests/AudioEngineTests.swift` (new)

## Goal

Cut idle CPU for a menu bar app that is closed most of the time, and give
`AudioEngine`'s user actions a test surface (previously 0% line coverage).

## Problem

`top -l 9` averaged **3.31% CPU** with the panel closed: the 10 Hz meter timer
published levels into `apps` even with no window, every 1 Hz refresh rebuilt the
row array and reassigned it (SwiftUI invalidated regardless of equality), and
`RunningAppDescriptor.snapshot` read `NSRunningApplication.icon` for every
running app every second (`_LSAliasCompareToNode` and LaunchServices bookmark
lookups dominated the sample).

`AudioEngine` owns every user action but had 551 uncovered lines, because its
tests would have to cross the HAL.

## Change

- `AudioEngine.setPanelVisible(_:)`, called from `PanelView.onAppear/onDisappear`.
  `tickMeters` returns immediately unless the panel is on screen.
- Rows and hidden apps are only published when they differ from the current
  values; an identical array no longer invalidates the panel once a second.
- `RunningAppDescriptor.snapshot(_:icon:)` takes an icon provider;
  `AudioEngine` passes a bundle-ID cache, so LaunchServices is hit once per app.
- `AudioEngineTests`: 11 tests over an isolated `UserDefaults` suite, covering
  volume/boost/balance clamping, mute and step-volume, EQ, night mode, mono,
  Audio Unit persistence, scene save/delete, EQ presets, and the “recording
  needs a tap” failure path.

## Verification

- `top -l 9 -s 1` with the panel closed: **3.31% → 1.84%** average on this Mac
  (second run 2.29; the machine is busy, treat ±0.5 as noise).
- `swift test`: 143 tests (11 new), all passing.
- `./scripts/check.sh`: OK.

## Boundaries

- No change to the 1 Hz refresh cadence or HAL listeners; rows still update
  while the panel is closed, they just do not repaint.
- Meters resume on the next tick after the panel appears; no history is kept.
- Tests must not call `refresh()`: it touches the HAL and would create real
  taps inside the test process.

## Maintenance

- New published state that changes every refresh must be compared before
  assignment; otherwise the panel repaints behind a closed window.
- A new `AudioEngine` action that ends with `refresh()` needs its own seam
  before it can be tested; do not add it to `AudioEngineTests` as-is.
