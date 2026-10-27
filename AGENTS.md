# AGENTS.md — Tapmix

## What this project is
A macOS 15+ menu bar app that controls per-app volume with Core Audio process
taps. No kernel extension, no virtual audio driver, no third-party dependencies.

## Commands
- `swift build`
- `swift test`
- `./scripts/check.sh` — tests + app bundle + signature verification
- `./scripts/build-app.sh` then `open build/Tapmix.app`
- `open` the `.app` bundle; launching the raw binary breaks TCC attribution.

## Architecture
- `AudioSystem` — HAL property wrappers and property listeners.
- `AudioCatalog` — pure snapshot → rows + per-bundle processes.
- `AppResolver` — pure helper-process → host-app resolution.
- `RunningAppDescriptor` — the only place that reads `NSRunningApplication`.
- `TapManager` — tap lifecycle, per-tap health, backoff, crossfaded routes.
- `TapController` — one tap + one private aggregate + one IO proc.
- `TapRender` — frame-major gain, EQ, night mode, balance/mono and limiter.
- `EQProcessor` — ten peaking biquads per channel, coefficients built off-thread.
- `NightModeProcessor` — stereo-linked leveler before the limiter.
- `EQSettings` — per-app bands, AutoEQ filters and presets; persisted in `AppLevel`.
- `EQFilterParser` — reads AutoEQ/Equalizer APO `ParametricEQ.txt` files.
- `AudioEngine` — 1s poll, UI state, user actions, hotkey target.
- `DuckingPolicy` — microphone-activity hysteresis; never reads audio.
- `DevicePriority` — switches to the preferred output when it reconnects.
- `HotKeyCenter`/`HotKeyController` — global Carbon hotkeys and their modifier setting.
- `HUDController` — the non-activating volume HUD.
- `SceneStore`/`MixScene` — named snapshots of per-app levels.
- `TapmixURLCommand`/`URLCommandRouter` — `tapmix://` automation.
- `PanelView`/`TapmixApp` — SwiftUI menu bar.

## Realtime invariants
`TapController.render` and `TapRender` must not allocate, lock, log, message
Objective-C, or call back into the main actor. Keep the tap interleaved Float32;
the start-time format guard enforces it. No `Array` inside the callback.

## Permissions
The app needs System Audio Recording (TCC). Launch via LaunchServices (`open`).
Ad-hoc rebuilds get a new TCC identity; use the stable signing recipe in README.
A tap with no callbacks after the 6s health window is retried with backoff;
other taps keep running.

## Conventions
Swift 5 language mode, SwiftPM, one type per file, no new dependencies, no
private APIs. `XCTest` with `@testable import TapmixCore`. Match the existing
small interfaces; do not add protocols unless a second adapter exists.

## Plans
Read `plans/README.md` first. Executors update their status row. The plans
predate git initialization, so they use the SHA-256 baseline from the initial
commit; future plans can use commits.
