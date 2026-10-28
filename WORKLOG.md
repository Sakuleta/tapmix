# Work log

Reverse chronological. One entry per work session: what shipped, how it was
found or decided, and the commands worth repeating. Implementation plans live in
`plans/`, release notes in `CHANGELOG.md` and on the GitHub releases.

## 2026-10-28 — 0.3.3: a row for apps LaunchServices does not list

**Report:** background audio was audible but the panel had no row for it.

**How it was found**

- A throwaway Swift probe read `kAudioHardwarePropertyProcessObjectList` and
  printed `kAudioProcessPropertyIsRunningOutput` for every process object. The
  only processes producing output were Tapmix (its own private aggregate) and
  `com.mardinli.TASO.dev`, an app running in the booted iPhone 17 simulator.
  Brave, Music and Spotify were silent at that moment.
- That process never appears in `NSWorkspace.runningApplications`
  (`NSRunningApplication(processIdentifier:)` returns `nil`), so
  `AppResolver.resolve` found no host and `AudioCatalog.groups` dropped the
  process before it could become a row.
- Reproduced with a deterministic fixture in `AudioCatalogTests` and, once, with
  a live probe in the test target; the probe was deleted afterwards.

**Fix**

- `AppResolver` now falls back to the process's own app bundle: the nearest
  `.app` ancestor of the `proc_pidpath` executable, required to be
  `CFBundlePackageType == APPL` and not nested inside another `.app` (so an
  orphan helper bundle stays hidden). Name comes from `CFBundleDisplayName` /
  `CFBundleName`, icon from the bundle path.
- Identity is cached per app path in an `NSCache`: `resolve` runs on the 1 s
  refresh and `Bundle` / icon reads hit LaunchServices.
- Tests: `testAppOutsideLaunchServicesAppears`,
  `testHelperBundleInsideHostIsStillHidden`.

**Release 0.3.3** — `NOTARY_PROFILE=tapmix ./scripts/release.sh 0.3.3`,
`gh release create v0.3.3 dist/Tapmix-0.3.3.zip`, appcast pushed, cask checksum
updated.

## 2026-10-27 — 0.3.0 → 0.3.2

**What shipped**

- 0.3.0: `TapPlan` as a pure module for which processes get a tap, realtime
  state published through `Synchronization.Atomic`, panel split by surface,
  recorder surviving a full disk / 4 GB, 11 engine action tests, idle CPU
  3.31% → 1.84%.
- 0.3.1: `MenuBarAnchor` pins the panel back under the menu bar; development
  builds moved to their own bundle ID (`com.mardinli.tapmix.dev`) so TCC stops
  re-prompting after every ad-hoc rebuild.
- 0.3.2: a process that captures the microphone plays untouched until the call
  ends, so WhatsApp calls stay at normal volume and echo cancellation keeps its
  reference.

**How it was done**

- A full audit of 0.2.4 produced plans 006–010 in `plans/` (see
  `plans/README.md` for findings, dispositions and rejected work); each plan was
  executed with its own verification.
- Each fix went through a branch and a PR with Problem / Change / Verification /
  Merge Danger, CI running `./scripts/check.sh`, then a squash merge titled after
  the PR (`Let calls play untouched (#48)`).
- Release: `Prepare <version>` commit bumps `CFBundleShortVersionString` and
  `CFBundleVersion` in `Resources/Info.plist`, adds the `CHANGELOG.md` entry and
  the cask checksum, then `NOTARY_PROFILE=tapmix ./scripts/release.sh` builds,
  signs, notarizes, staples and rewrites `docs/appcast.xml`.
- `gh release create v<version> dist/Tapmix-<version>.zip` carries the notes and
  the SHA-256; the appcast is pushed afterwards so the feed points at an asset
  that already exists.
