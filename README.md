# Tapmix

An open-source, SoundSource-style per-app volume mixer for macOS, living in the
menu bar. Built from scratch on Apple's public Core Audio **process tap** APIs —
no kernel extension, no virtual audio driver, and no proprietary code.

[github.com/Sakuleta/tapmix](https://github.com/Sakuleta/tapmix) · MIT licensed

![status](https://img.shields.io/badge/status-v0.1-orange) ![license](https://img.shields.io/badge/license-MIT-blue)

## Features (v0.1)

- **Per-app volume** from 0% to 200% (100% is unity gain)
- **Per-app mute** with a 20 ms click-free gain ramp
- **Output volume and mute** for the current default output device
- **Automatic app discovery** — apps appear when they start playing and stay
  while their process is alive or a level is stored
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
```

### Permissions

The first time an app is tapped, macOS asks for **System Audio Recording**
permission (System Settings → Privacy & Security → Screen & System Audio
Recording). If the prompt takes longer than a few seconds or you dismiss it,
Tapmix stops the affected tap and shows a permission banner with **Open
Settings** and **Retry** buttons. Allow Tapmix in System Settings, then press
**Retry** to recreate that tap.

The app bundle must be launched through LaunchServices (`open Tapmix.app`)
so the permission is attributed to Tapmix, not to Terminal. Ad-hoc signing
means each rebuild has a new code hash, so macOS may ask again after a rebuild.
Set `CODESIGN_IDENTITY` to a stable self-signed certificate if that becomes
annoying:

```bash
CODESIGN_IDENTITY="My Self-Signed Cert" ./scripts/build-app.sh
```

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

`AudioMath.process` is a small, allocation-free, real-time-safe buffer routine
with mono/stereo/multichannel conversion. It is covered by unit tests, including
gain clamping, silence fill, and mute ramps.

```
Sources/
  TapmixCore/          # Audio engine, HAL plumbing, persistence (no UI)
    AudioSystem.swift    # Process/device properties, default output volume
    TapController.swift  # Tap + private aggregate + IO proc for one process
    AudioEngine.swift    # Polling, grouping, lifecycle, permission health
    AudioMath.swift      # Real-time gain stage (unit tested)
    AppResolver.swift    # Maps helper processes to their host application
    Models.swift         # AppRow, AppLevel, LevelStore
  Tapmix/              # SwiftUI menu bar app
Tests/TapmixTests/
```

## Known limitations

- **Stereo only.** Multichannel outputs are handled, but the tap is a stereo
  mixdown, so 5.1/7.1 content is downmixed by Core Audio.
- **Boost clips.** Above 100%, samples are hard-clamped; there is no lookahead
  limiter yet.
- **Per-process, not per-app.** A browser tab cannot be controlled separately
  from another tab in the same browser; all processes belonging to one host app
  share a slider.
- **No routing or EQ yet.** Every controlled app plays to the current default
  output device.
- **Output volume depends on the device.** The slider uses the HAL volume
  property; some HDMI/USB interfaces expose no software volume and ignore it.
- **Polling every second.** Fine for a menu bar utility; HAL listeners are a
  later optimization.
- **Ad-hoc signing.** TCC grants do not survive rebuilds without a stable
  identity.

## Roadmap

1. Per-app output device routing (aggregate per target device)
2. 10-band EQ and boost presets with a soft limiter
3. HAL listeners instead of polling; hotplug and sample-rate handling
4. Global hotkeys and a volume HUD
5. Pinned/active app list and ignore list
6. Notarized, Developer ID-signed release

## License

MIT. See [LICENSE](LICENSE). SoundSource is a trademark of Rogue Amoeba
Software; this project is not affiliated with or endorsed by Rogue Amoeba.
