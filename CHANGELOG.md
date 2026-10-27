# Changelog

## 0.3.1 — 2026-10-27

- The panel opens attached to the menu bar; a stale window frame after the app
  list changed while it was closed no longer leaves it one bar-height lower

## 0.3.0 — 2026-10-27

- Tap planning is a pure `TapPlan` module; a failed HAL process read keeps the
  running mix instead of stopping every tap
- The recording dot follows the recorder that owns it, so it clears when a tap
  stops
- EQ banks and the recording ring publish through atomics; a tap stops before
  its Audio Unit and recorder are released
- The panel keeps its contrast over bright windows and is split by surface
- Mixer sliders are drawn instead of the system track, so they read in light mode
- Idle CPU with the panel closed drops from 3.3% to 1.8%
- 145 tests, including engine actions; a recording ends cleanly at 4 GB or when
  the disk fills
- Hotkey volume steps respect call ducking

## 0.2.4 — 2026-10-27

- The menu bar panel is translucent glass: the system material shows through,
  the output device floats on a Liquid Glass card on macOS 26, and the volume
  HUD uses the same treatment
- Rows and controls answer the pointer with a short hover highlight and a press
  scale; both respect Reduce Motion
- Tighter panel height, softer row borders and a real empty state for a search
  with no matches

## 0.2.3 — 2026-10-27

- Call ducking only triggers for conferencing apps and browsers; recorders
  that hold the microphone (Hex, screen recorders, virtual drivers) no longer
  lower the mix
- Per-process microphone detection replaces the device-wide flag

## 0.2.2 — 2026-10-27

- Audio Unit effects: host an installed AUv2 effect per app from a searchable sheet
- Sparkle auto-update with an EdDSA-signed appcast on GitHub Pages
- Local AutoEQ folder catalog with search
- WAV recording now writes frames; it previously produced an empty file
- Homebrew cask pinned to the notarized release

## 0.2.1 — 2026-10-27

- EQ response curve above the bands, including imported AutoEQ filters
- AutoEQ attribution and third-party notices
- Notarized Developer ID release

## 0.2.0 — 2026-10-27

- Per-app routing with crossfaded device switches
- 10-band EQ, presets and AutoEQ `ParametricEQ.txt` import
- Night mode, balance/mono, call ducking and device priority
- Saved mixes, global hotkeys with HUD and `tapmix://` automation
- Launch at login, app icon, CI and notarized release tooling
