# Tapmix

An open-source, SoundSource-style per-app volume mixer for macOS, living in the
menu bar. Built from scratch on Apple's public Core Audio **process tap** APIs —
no kernel extension, no virtual audio driver, and no proprietary code.

[github.com/Sakuleta/tapmix](https://github.com/Sakuleta/tapmix) · MIT licensed

![status](https://img.shields.io/badge/status-v0.1-orange) ![license](https://img.shields.io/badge/license-MIT-blue)

## Features (v0.1)

- **Per-app volume** from 0% to 200% (100% is unity gain)
- **Per-app boost** from 1x to 4x, protected by a 5 ms lookahead limiter
- **Per-app mute** with a 20 ms click-free gain ramp
- **Live per-app level meter** under each slider
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
permission again. Create a self-signed **Code Signing** certificate once:

1. Keychain Access → Certificate Assistant → Create a Certificate.
2. Name: `Tapmix Dev`; Identity Type: Self Signed Root; Certificate Type:
   Code Signing. Create it.
3. Select the certificate → Get Info → Trust → set "When using this
   certificate" to **Always Trust** for code signing.
4. Confirm it is usable:
   `security find-identity -v -p codesigning | grep "Tapmix Dev"`.
5. `./scripts/build-app.sh` picks it up automatically. Override with
   `CODESIGN_IDENTITY="..."` if you use a different identity.

If `codesign` reports a trust or identity error, fall back to ad-hoc for that
build; do not disable SIP or modify system security settings.

### The app list

- A row stays while the app's process is alive and has an active tap, or while
  a level is stored; it is not removed the moment playback pauses.
- The green dot means the app is currently playing; a gray dot means the row is
  kept for an active tap or a stored level.
- Taps are created on first playback; an existing tap is kept while the process
  lives.

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
2. A **private aggregate device** combines that tap with the current default
   output device. No device shows up in Audio MIDI Setup or in other apps.
3. An `AudioDeviceIOProc` receives the tap audio on the real-time HAL thread,
   applies a ramped gain, and writes it to the output buffers.
4. Tearing down the tap restores the app's normal audio path. Taps are removed
   when the process exits, the output device changes, or Tapmix quits.

`TapRender` is a small, allocation-free, frame-major buffer routine with
mono/stereo conversion and one gain ramp per frame, so planar outputs stay
balanced. It is covered by unit tests, including channel mapping, clamping,
silence fill, and mute ramps.

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
- **No routing or EQ yet.** Every controlled app plays to the current default
  output device.
- **Output volume depends on the device.** The slider uses the HAL volume
  property; some HDMI/USB interfaces expose no software volume and ignore it.
- **Polling discovery.** The app list refreshes every second and meters at
  10 Hz; HAL listeners are a later optimization.
- **Signing.** Ad-hoc signing is the fallback; TCC grants do not survive
  rebuilds without the stable identity described above.

## Roadmap

1. Per-app output device routing (aggregate per target device)
2. 10-band EQ, presets and loudness matching
3. HAL listeners instead of polling; hotplug and sample-rate handling
4. Global hotkeys and a volume HUD
5. Pinned/active app list and ignore list
6. Notarized, Developer ID-signed release

## License

MIT. See [LICENSE](LICENSE). SoundSource is a trademark of Rogue Amoeba
Software; this project is not affiliated with or endorsed by Rogue Amoeba.
