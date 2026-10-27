# Manual test checklist

These checks need real audio hardware or a second person; CI cannot cover them.

## Routing and devices

- [ ] Route one app to headphones and another to speakers; confirm each plays only on its device.
- [ ] Change one app's route while it plays; confirm the old device fades out and the new one fades in without silence.
- [ ] Disconnect the routed device; the app should fall back to the system default.
- [ ] Reconnect it; the app should return to it.
- [ ] Pin a preferred output; reconnect it and confirm the system default follows.
- [ ] Switch the system default while unrouted apps play; they follow, routed apps stay.

## Calls and microphone

- [ ] Join a Zoom/Teams/FaceTime call; other apps duck to ~30% after one second.
- [ ] End the call; levels restore 1.5 seconds later.
- [ ] The call app is not ducked.
- [ ] A browser-based call exempts the browser.
- [ ] Toggle call ducking off from the footer; nothing changes during a recording.

## EQ and sound

- [ ] Move a band; the response curve follows and audio changes.
- [ ] Import a `ParametricEQ.txt`; the curve changes and Clear restores it.
- [ ] Save an EQ preset on one app, apply it to another.
- [ ] Night mode lifts quiet dialogue and does not pump audibly on music.
- [ ] Boost 2x/4x stays clean on loud material (limiter).
- [ ] Balance and Mono behave on a single earbud.

## Lifecycle

- [ ] Put the Mac to sleep during playback and wake it; taps recover.
- [ ] Change the output sample rate in Audio MIDI Setup; playback stays clean.
- [ ] Leave playback running for an hour; CPU and memory stay flat.
- [ ] Quit from the panel while playing; audio fades instead of clicking.
- [ ] Toggle Launch at login, reboot, confirm the app starts; toggle it off again.

## Accessibility and UI

- [ ] VoiceOver names both sliders, mute, boost, EQ, output and search.
- [ ] Search filters rows and the panel does not resize.
- [ ] Save a scene, change levels, apply the scene; every value returns.
- [ ] The panel fits on a 1280x800 display with the EQ popover open.
