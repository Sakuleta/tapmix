# Tapmix

An open-source, SoundSource-style per-app volume mixer for macOS, living in the
menu bar. Built from scratch on Apple's public Core Audio **process tap** APIs —
no kernel extension, no virtual audio driver, and no proprietary code.

[github.com/Sakuleta/tapmix](https://github.com/Sakuleta/tapmix) · MIT licensed

![CI](https://github.com/Sakuleta/tapmix/actions/workflows/ci.yml/badge.svg) ![status](https://img.shields.io/badge/status-v0.2-orange) ![license](https://img.shields.io/badge/license-MIT-blue)

## Features (v0.1)

- **Per-app volume** from 0% to 200% (100% is unity gain)
- **Per-app boost** from 1x to 4x, protected by a 5 ms lookahead limiter
- **Per-app mute** with a 20 ms click-free gain ramp
- **Live per-app level meter** under each slider
- **10-band equalizer** per app with Flat, Bass Boost, Vocal Clarity, Treble
  and Loudness presets
- **Per-app output routing** — send one app to the speakers and another to
  headphones, or leave both on the system default
- **Global hotkeys and a volume HUD** — change the audible (or frontmost) app
  from any space without opening the panel
- **Automatic call ducking** — while the microphone is in use, other apps drop
  to 30% and return when the call ends
- **Preferred output** — pin a device and Tapmix switches back to it when it
  reconnects
- **Night mode** per app — lift quiet dialogue and tame loud peaks
- **AutoEQ import** — load a `ParametricEQ.txt` headphone correction per app
- **URL automation** — control volume, mute, boost and routing from Shortcuts,
  Raycast or shell scripts
- **Per-app balance and mono downmix** — shift left/right or fold to one channel
- **Saved mixes** — name a scene and restore levels, EQ and routing later
- **Custom EQ presets** — save bands plus AutoEQ filters and reuse them on any app
- **EQ response curve** — see the combined band/AutoEQ response while editing
- **Local AutoEQ catalog** — point Tapmix at an AutoEQ results folder and search it
- **Launch at login** — start Tapmix with the Mac from the gear menu
- **Pinned apps** stay visible while idle; **hide** an app to remove it from
  Tapmix entirely; **search** filters the list
- **Output volume and mute** for the current default output device
- **Automatic app discovery** — apps appear when they start playing and stay
  while they have an active tap or a stored level
- **Persistent levels** keyed by bundle ID, including helper/XPC processes
  (Chrome, Electron, Safari WebContent, …)
- **Menu bar only** — no Dock icon, no background agents

Planned next: per-app output routing, 10-band EQ, boost presets, hotkeys,
pinned apps, and a volume HUD. See [Roadmap](#roadmap).

## Build and run

Requirements: macOS 15+ (tested on macOS 27), Xcode command line tools.

```bash
./scripts/build-app.sh
open build/Tapmix.app
```

The script builds with SwiftPM, wraps the binary in a minimal `.app` bundle with
`Info.plist`, and ad-hoc signs it. Click the waveform icon in the menu bar.

For development:

```bash
swift build
swift test
./scripts/check.sh   # tests + app bundle + signature verification
```

### Permissions

The first time an app is tapped, macOS asks for **System Audio Recording**
permission (System Settings → Privacy & Security → Screen & System Audio
Recording). The prompt appears when the first aggregate with a tap starts, not
necessarily at launch. If the prompt takes longer than the health window, the
panel shows a banner. After allowing, press **Retry**; Tapmix then recreates
only the stalled tap and leaves healthy ones running.

If permission was denied, allow it in System Settings → Privacy & Security →
Screen & System Audio Recording. If Tapmix looks stale in that list, remove it
with the minus button and relaunch.

The app bundle must be launched through LaunchServices (`open Tapmix.app`)
so the permission is attributed to Tapmix, not to Terminal.

### Stable local signing (recommended)

Ad-hoc signing gets a new code hash on every rebuild, so macOS asks for audio
permission again. If the Mac already has an **Apple Development** identity
(Xcode → Settings → Accounts), `build-app.sh` picks it automatically and the TCC
grant survives rebuilds. Otherwise create a self-signed **Code Signing**
certificate once:

1. Keychain Access → Certificate Assistant → Create a Certificate.
2. Name: `Tapmix Dev`; Identity Type: Self Signed Root; Certificate Type:
   Code Signing. Create it.
3. Select the certificate → Get Info → Trust → set "When using this
   certificate" to **Always Trust** for code signing.
4. Confirm it is usable:
   `security find-identity -v -p codesigning | grep "Tapmix Dev"`.
5. `./scripts/build-app.sh` picks it up automatically. Override with
   `CODESIGN_IDENTITY="..."` if you use a different identity; an Apple
   Development identity is used when no `Tapmix Dev` certificate exists.

If `codesign` reports a trust or identity error, fall back to ad-hoc for that
build; do not disable SIP or modify system security settings.

### The app list

- A row stays while the app's process is alive and has an active tap, or while
  a level is stored; it is not removed the moment playback pauses.
- The green dot means the app is currently playing; a gray dot means the row is
  kept for an active tap or a stored level.
- Taps are created on first playback; an existing tap is kept while the process
  lives.

### Hotkeys

- `⌥⌘↑` / `⌥⌘↓` — raise or lower the active app by 5%. The active app is the
  one currently producing audio; if nothing plays, the frontmost app that
  Tapmix lists.
- `⌥⌘M` — mute or unmute that app.
- A small HUD appears near the top of the screen with the app name and level.

Choose the modifier set from the keyboard menu in the footer: `⌥⌘`
(default), `⌃⌥`, `⇧⌘` or **Off**. The choice is remembered. Hotkeys need no
Accessibility permission.

### Automation

The `tapmix://` scheme accepts the app's bundle ID:

```bash
open "tapmix://set-volume?app=com.spotify.client&volume=40"
open "tapmix://step-volume?app=com.spotify.client&delta=-5"
open "tapmix://toggle-mute?app=com.spotify.client"
open "tapmix://set-boost?app=com.brave.Browser&boost=2"
open "tapmix://set-route?app=com.spotify.client&device=DEVICE-UID"
```

`volume` is 0-200, `boost` is 1-4, and an empty `device` returns the app to
the system default. The same strings work in Shortcuts and Raycast.

### EQ response

The graph above the bands plots the combined 10-band and AutoEQ response from
20 Hz to 20 kHz, with the zero line in the middle and ±12 dB grid lines. It
updates while a slider moves.

### EQ presets

The **Presets** menu in the sound popover lists the built-in presets, saved
presets, and **Save preset…**. A saved preset stores the bands and any imported
AutoEQ filters, is overwritten by name, and can be applied to any app or
deleted from the same menu.

### AutoEQ

In an app's sound popover choose **Import AutoEQ…** and pick a
`ParametricEQ.txt` exported by AutoEQ or Equalizer APO. Up to 24 `PK`, `LSC`
and `HSC` filters are applied on top of the 10 bands, stored per app, and kept
even when the 10-band switch is off. **Clear** removes the import. The file's
`Preamp` line is ignored; the limiter provides the headroom.

To search a downloaded AutoEQ results folder, choose **AutoEQ → Browse
folder…** once; Tapmix indexes the `ParametricEQ.txt` files locally and opens a
searchable catalog. Nothing is downloaded by Tapmix.

### Launch at login

Use the gear menu in the footer. Keep the app in `/Applications` for the most
reliable registration; moving it out of the build folder also keeps the TCC
grant and login item stable. If macOS rejects the change, the panel shows the
error.

### Scenes

The theater-masks menu next to the header saves the current mix: levels, boost,
EQ, AutoEQ filters, routing, night mode, balance and mono for every adjusted
app. Pick a scene to restore it, or delete scenes from the same menu. Scenes
are stored locally and also apply to apps that are not running yet.

### Balance and mono

The same sound popover has an L/R balance slider and a **Mono** switch. Mono
folds both channels together, which keeps a podcast audible in one earbud;
balance is applied after the fold.

### Night mode

Open an app's EQ popover and switch on **Night mode**. Quiet material gets a
+3.5 dB lift, peaks above about -18 dBFS are compressed 4:1, and the existing
limiter catches what is left. It is meant for late-night video and podcasts,
not for critical listening.

### Preferred output

Click the arrow icon next to the output name and pick a device. When that
device connects, Tapmix makes it the system default. A manual switch while it
is connected is respected; Tapmix only acts when the device appears again.
Choose **Follow macOS** to turn the preference off.

### Calls

When any app starts using the microphone, Tapmix waits a second, then lowers
every other app to 30%. The conferencing app (Zoom, Teams, FaceTime, Discord,
Slack, WhatsApp, Webex) and the app that was frontmost when the microphone
started are never ducked. Everything returns to its previous level 1.5 seconds
after the microphone is released.

Tapmix only asks the HAL whether an input device is running; it never reads
microphone audio. Turn the feature off from the speaker-with-one-wave menu in
the panel footer. Screen recordings and voice memos also count as microphone
use.

### Manual test checklist

Hardware-dependent checks (routing, Bluetooth, calls, sleep/wake, long runs) are
listed in [docs/manual-test.md](docs/manual-test.md).

### Troubleshooting

- **No apps listed:** start playback in the app and check the menu bar icon;
  verify the output device in Sound settings is the one you expect.
- **No audio change:** another virtual driver (Background Music, BlackHole,
  SoundSource) may be the default output; see the note below.
- **Permission banner stays:** press **Retry**; if it returns, reset the
  Screen & System Audio Recording entry for Tapmix and relaunch.
- **Something else:** run `./scripts/check.sh` for tests, bundle and signature
  verification before filing an issue.

### Don't stack audio drivers

If another virtual driver (Background Music, BlackHole, SoundSource's ACE) is
the default output, Tapmix taps the app before that driver and plays into
it. It works, but you are stacking two mixers. For predictable results, choose
the real output device (speakers/headphones) while testing.

## How it works

For every process that is producing audio:

1. `CATapDescription(stereoMixdownOfProcesses:)` creates a **private process
   tap** with `muteBehavior = .mutedWhenTapped`. macOS silences the app's direct
   hardware path only while the tap is being read.
2. A **private aggregate device** combines that tap with the app's target
   output device (the system default unless the app is routed). No device shows
   up in Audio MIDI Setup or in other apps.
3. An `AudioDeviceIOProc` receives the tap audio on the real-time HAL thread,
   applies a ramped gain, and writes it to the output buffers.
4. Tearing down the tap restores the app's normal audio path. Taps are removed
   when the process exits, the output device changes, or Tapmix quits.

`TapRender` is a small, allocation-free, frame-major buffer routine with
mono/stereo conversion and one gain ramp per frame, so planar outputs stay
balanced. `EQProcessor` adds ten peaking filters per channel before the limiter;
coefficients are rebuilt on the main thread and handed to the callback. Both
paths are covered by unit tests, including channel mapping, clamping, mute ramps
and a +6 dB center-frequency check.

```
Sources/
  TapmixCore/                    # Audio engine, HAL plumbing, persistence (no UI)
    AudioSystem.swift              # Process/device properties, default output volume
    AudioCatalog.swift             # Pure grouping: processes → rows
    AppResolver.swift              # Pure helper-process → host-app resolution
    RunningAppDescriptor.swift     # Value snapshot of NSRunningApplication
    TapManager.swift               # Tap lifecycle, per-tap health, retry backoff
    TapController.swift            # Tap + private aggregate + IO proc for one process
    TapRender.swift                # Frame-major realtime renderer (unit tested)
    AudioMath.swift                # Gain clamp and ramp coefficient
    AudioEngine.swift              # Polling, UI state, user actions
    Models.swift                   # AppRow, AppLevel, LevelStore
  Tapmix/                         # SwiftUI menu bar app
Tests/TapmixTests/
```

## Known limitations

- **Stereo only.** Multichannel outputs are handled, but the tap is a stereo
  mixdown, so 5.1/7.1 content is downmixed by Core Audio.
- **Boost is limited, not loudness-matched.** Up to 8x total gain is protected
  by a lookahead limiter; very dynamic material can still pump.
- **Per-process, not per-app.** A browser tab cannot be controlled separately
  from another tab in the same browser; all processes belonging to one host app
  share a slider.
- **Output volume depends on the device.** The slider uses the HAL volume
  property; some HDMI/USB interfaces expose no software volume and ignore it.
- **Route changes crossfade.** The old tap fades out and stops after 60 ms
  while the new tap starts on the target device.
- **HAL listeners plus a safety poll.** Device, default-output and process
  changes arrive immediately; a one-second timer remains for ducking and as a
  fallback, and meters update at 10 Hz.
- **Call detection is microphone-based.** Any recording app can trigger
  ducking, and a browser-based call exempts the whole browser.
- **Device priority reacts to connections only.** It does not fight a manual
  output switch while the preferred device stays connected.
- **Night mode is a compressor, not loudness matching.** Heavy use can pump;
  it is opt-in per app.
- **AutoEQ import handles PK/LSC/HSC only.** Shelf Q is not used, and the
  preamp gain is left to the limiter.
- **Signing.** Ad-hoc signing is the fallback; TCC grants do not survive
  rebuilds without the stable identity described above.

## Release

```bash
./scripts/release.sh            # uses CFBundleShortVersionString
./scripts/release.sh 0.2.1      # explicit version
```

The script builds a release bundle, signs it, and writes
`dist/Tapmix-<version>.zip` with a SHA-256. Without a Developer ID it produces
a local development zip. For notarization, store credentials once and set the
profile:

```bash
xcrun notarytool store-credentials "tapmix" \
  --apple-id "you@example.com" --team-id TEAMID --password APP_SPECIFIC_PASSWORD

NOTARY_PROFILE=tapmix ./scripts/release.sh
```

## Roadmap

1. A searchable AutoEQ catalog and editable parametric filters
2. Configurable hotkeys and media-key handling
3. Notarized, Developer ID-signed release

## Credits

AutoEQ import supports the `ParametricEQ.txt` format from
[AutoEQ](https://github.com/jaakkopasanen/AutoEq) by Jaakko Pasanen (MIT).
Tapmix does not bundle AutoEQ measurement data. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

MIT. See [LICENSE](LICENSE). SoundSource is a trademark of Rogue Amoeba
Software; this project is not affiliated with or endorsed by Rogue Amoeba.
