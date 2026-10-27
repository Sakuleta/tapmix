# Plan 005: Stable local signing, a check script, and honest docs

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If a
> STOP condition occurs, stop and report — do not improvise.
>
> **Drift check (run first)**: pre-git planning snapshot; compare the SHA-256 hashes below:
> `a84df2cd42acc4c7befee6f8dc9d09bd2b3ec697c3bd899df9663a50948f8926  scripts/build-app.sh`
> `8c15fcc99944f169a0b3d49de4f3cbf9f1affc8cab196c0b0c3c533e1bb74ba3  README.md`
> If either hash differs, compare the excerpts below before editing.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: plans/002, 003, 004 (for the final project layout in README)
- **Category**: dx + docs
- **Planned at**: pre-git snapshot, 2026-10-27
- **Issue**: not published

## Why this matters

Ad-hoc signing changes the code hash on every rebuild, so macOS treats each build
as a new app and asks for System Audio Recording again. That happened twice
during development and interrupts every manual test. The build script already
accepts `CODESIGN_IDENTITY`, but there is no documented way to create a stable
identity, and ad-hoc is the silent default. There is also no single command that
runs tests, builds the bundle and verifies the signature.

The docs also need to match the code: rows persist for apps that have a stored
level or an active tap, the permission banner may appear after a slow first-run
consent, and Retry is the recovery path. This plan adds the signing recipe, a
`check.sh` verification baseline, and an `AGENTS.md` so future agents do not
rediscover the RT-safety and permission rules.

## Current state

`scripts/build-app.sh` signs ad-hoc unless `CODESIGN_IDENTITY` is set:

```bash
IDENTITY="${CODESIGN_IDENTITY:--}"
...
codesign --force --sign "$IDENTITY" --identifier com.sakuleta.tapmix "$APP"
```

`README.md:53-61` says "Set `CODESIGN_IDENTITY` to a stable self-signed
certificate if that becomes annoying" but never explains how to create one.
`README.md:19` says "apps appear when they start playing"; in practice a row
stays while its process has an active tap or a stored level, with a green dot
showing whether it is currently playing. `README.md:48-55` does not explain that
the prompt may appear only when an app starts playing, or that a slow prompt can
show the in-app banner.

There is no `AGENTS.md`, no `scripts/check.sh`, and the project has no linter or
formatter. Do not add those; this plan is limited to signing, verification, and
accurate documentation.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Tests | `swift test` | all pass |
| Full check | `./scripts/check.sh` | `check: OK` |
| Signing identities | `security find-identity -v -p codesigning` | list or empty |
| Signature | `codesign -dv build/Tapmix.app` | identity or `adhoc` |

## Scope

**In scope**:
- `scripts/build-app.sh`
- `scripts/check.sh` (create)
- `README.md`
- `AGENTS.md` (create)

**Out of scope**:
- Any Swift source file.
- Creating a certificate or changing keychain trust from a script. The
  certificate is a one-time **human** step documented in the README.
- CI, lint, formatter, notarization, app icon.
- Initializing git. If the operator does that separately, plans can add commit
  stamps later.

## Steps

### Step 1: Make stable identity the default when it exists

Replace the identity block in `scripts/build-app.sh` with:

```bash
CONFIG="${1:-release}"
APP="build/Tapmix.app"
DEFAULT_IDENTITY="Tapmix Dev"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    IDENTITY="$CODESIGN_IDENTITY"
elif security find-identity -v -p codesigning 2>/dev/null | grep -Fq "$DEFAULT_IDENTITY"; then
    IDENTITY="$DEFAULT_IDENTITY"
else
    IDENTITY="-"
    echo "warning: using ad-hoc signing; macOS may ask for audio permission after each rebuild."
    echo "         Create a 'Tapmix Dev' code-signing certificate (see README) or set CODESIGN_IDENTITY."
fi
```

Change the final line to include the identity:

```bash
echo "Built $APP (signed with: $IDENTITY)"
echo "Run with: open $APP"
```

The fallback remains ad-hoc, so fresh clones still build. Do not auto-create the
certificate.

**Verify**:
- `./scripts/build-app.sh` → exits 0; prints either "signed with: Tapmix Dev"
  or the ad-hoc warning.
- `codesign -dv build/Tapmix.app 2>&1 | grep -E "Authority|Signature"` → shows
  the identity when present, otherwise `Signature=adhoc`.

### Step 2: Add the one-command check

Create `scripts/check.sh`:

```bash
#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

swift test
./scripts/build-app.sh
codesign --verify --strict build/Tapmix.app

echo "check: OK"
```

Make both scripts executable (`chmod +x scripts/build-app.sh scripts/check.sh`).

**Verify**: `./scripts/check.sh` → tests pass, bundle builds, signature verifies,
last line `check: OK`.

### Step 3: Document stable signing and the real app-list behaviour

In `README.md`, replace the signing paragraph with a short section:

```markdown
### Stable local signing (recommended)

Ad-hoc signing gets a new code hash on every rebuild, so macOS asks for audio
permission again. Create a self-signed **Code Signing** certificate once:

1. Keychain Access → Certificate Assistant → Create a Certificate.
2. Name: `Tapmix Dev`; Identity Type: Self Signed Root; Certificate Type:
   Code Signing. Create it.
3. Select the certificate → Get Info → Trust → set “When using this
   certificate” to **Always Trust** for code signing.
4. Confirm it is usable:
   `security find-identity -v -p codesigning | grep "Tapmix Dev"`.
5. `./scripts/build-app.sh` picks it up automatically. Override with
   `CODESIGN_IDENTITY="..."` if you use a different identity.

If `codesign` reports a trust or identity error, fall back to ad-hoc for that
build; do not disable SIP or modify system security settings.
```

Add `./scripts/check.sh` to the development commands:

```bash
swift build
swift test
./scripts/check.sh   # tests + app bundle + signature verification
```

Clarify the app list:

- A row stays while the app's process is alive and has an active tap, or while a
  level is stored; it is not removed the moment playback pauses.
- The green dot means the app is currently playing; a gray dot means the row is
  kept for an active tap/stored level.
- Taps are created on first playback; an existing tap is kept while the process
  lives.

Clarify the permission flow (replace the existing permission paragraph):

- The prompt appears when the first aggregate with a tap starts, not necessarily
  at launch.
- If the prompt takes longer than the health window, the panel shows a banner.
  After allowing, press **Retry**; the app then recreates only the stalled tap.
- If permission was denied, allow it in System Settings → Privacy & Security →
  Screen & System Audio Recording. If the app is stale, remove it with the minus
  button and relaunch.

Add a troubleshooting list with four items: output device check, other virtual
drivers, permission reset, and `./scripts/check.sh`.

Update the project layout block to include the files that exist after plans
002–004: `TapManager.swift`, `TapRender.swift`, `AudioCatalog.swift`,
`RunningAppDescriptor.swift`. If those plans have not landed yet, STOP this plan
and run it last — the README must not describe files that do not exist.

**Verify**:
- `grep -n "Tapmix Dev\|check.sh\|green dot\|Retry" README.md` → all present.
- `grep -n "TapManager.swift\|TapRender.swift\|AudioCatalog.swift\|RunningAppDescriptor.swift" README.md` → all present.

### Step 4: Add AGENTS.md

Create `AGENTS.md` at the repository root with these sections (adapt the layout
list to the files that exist after 002–004):

```markdown
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
- `AudioSystem` — HAL property wrappers (processes, device volume/mute).
- `AudioCatalog` — pure snapshot → rows + per-bundle processes.
- `AppResolver` — pure helper-process → host-app resolution.
- `TapManager` — tap lifecycle, per-tap health, backoff, output rebuild.
- `TapController` — one tap + one private aggregate + one IO proc.
- `TapRender` — frame-major buffer copy/gain; the realtime seam.
- `AudioEngine` — 1s poll, UI state, user actions.
- `PanelView`/`TapmixApp` — SwiftUI menu bar.

## Realtime invariants
`TapController.render` and `TapRender` must not allocate, lock, log, message
Objective-C, or call back into the main actor. Keep the tap interleaved Float32;
the start-time format guard enforces it. No `Array` inside the callback.

## Permissions
The app needs System Audio Recording (TCC). Launch via LaunchServices (`open`).
Ad-hoc rebuilds get a new TCC identity; use the stable signing recipe in README.

## Conventions
Swift 5 language mode, SwiftPM, one type per file, no new dependencies, no
private APIs. `XCTest` with `@testable import TapmixCore`. Match the existing
small interfaces; do not add protocols unless a second adapter exists.

## Plans
Read `plans/README.md` first. Executors update their status row. The plans predate
git initialization, so they use the SHA-256 baseline from the initial commit;
future plans can use commits.
```

The repository now has git and a public remote. Do not rewrite history.

**Verify**: `grep -n "Realtime invariants\|TapRender\|check.sh" AGENTS.md` → present.

## Test plan

- `./scripts/check.sh` is the new verification baseline: it runs the full test
  suite, rebuilds the bundle, and verifies the signature.
- No new Swift tests; this plan changes scripts/docs only.
- Manual: with a stable identity, rebuild twice and confirm macOS does not ask
  for audio permission again. This is user-confirmed, not automatable; if the
  identity is absent, the ad-hoc warning is expected.

## Done criteria

- [ ] `./scripts/check.sh` exits 0 and prints `check: OK`.
- [ ] `scripts/build-app.sh` prefers `Tapmix Dev` when it exists; ad-hoc
  fallback still works on a machine without it.
- [ ] `codesign --verify --strict build/Tapmix.app` exits 0.
- [ ] README explains stable signing, row persistence, the permission/Retry
  flow, and troubleshooting.
- [ ] `AGENTS.md` has commands, architecture, RT invariants, permission notes,
  conventions and the plans pointer.
- [ ] No Swift source file is modified.
- [ ] `README.md`'s project layout lists only files that exist at execution time.

## STOP conditions

Stop and report if:

- `security find-identity` finds `Tapmix Dev` but `codesign` fails because the
  certificate is untrusted. Do not modify keychain trust from the script; leave
  the ad-hoc fallback and report the exact `codesign` error.
- `codesign --verify --strict` fails on the ad-hoc bundle (it passed during the
  audit; a failure indicates a packaging change).
- Plans 002–004 have not landed and the README layout would describe missing
  files. Run this plan last.
- A README change would require inventing behavior that is not in the code.

## Maintenance notes

- The build script's default identity name is a convention; changing it means
  updating the README and the `DEFAULT_IDENTITY` variable together.
- `check.sh` is the single verification command; extend it rather than adding a
  second script.
- Keep `AGENTS.md` aligned with the architecture after future refactors; it is
  the first file a new agent reads.
- Git is still absent. If the operator initializes it, add commit stamps to the
  plans and replace the SHA-256 drift checks with commits in future plans.
