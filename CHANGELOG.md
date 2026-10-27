# Changelog

## Unreleased

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
