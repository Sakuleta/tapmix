# 008 — Panel contrast and file split

**Status:** DONE
**Baseline:** 4152bb6 (after 006)
**Touches:** `Sources/Tapmix/DesignSystem.swift`, `PanelView.swift`,
`AppRowView.swift` (new), `EQPanel.swift` (new), `Pickers.swift` (new),
`SearchField.swift` (new)

## Goal

Keep the glass panel readable over bright windows, and stop one 1,141-line file
from holding nine types.

## Problem

0.2.4 removed the opaque window background so the system material could show
through. The material blends with whatever sits behind the panel: over a white
browser window the surface lifted to roughly `#8a8a8a` while the text stayed
white, which reads at about 1.6:1 — effectively unreadable. The same file also
mixed the panel, the app row, the EQ popover, the response curve, the AppKit
search bridge and two pickers, against the project's one-type-per-file rule.

## Change

- `PanelSurface` adds an appearance-aware scrim under the content: 30% black in
  dark mode, 50% white in light mode. The worst case above becomes `#616161`
  (about 6:1 against white text) in dark mode; light mode keeps black text on a
  light surface even over a dark window.
- The file split by surface, no behaviour change and no new types:
  - `PanelView.swift` — panel shell, header, output card, app list, footer (411)
  - `AppRowView.swift` — row + level meter (272)
  - `EQPanel.swift` — EQ popover + curve shapes (321)
  - `Pickers.swift` — AutoEQ catalog and Audio Unit picker (111)
  - `SearchField.swift` — `NSSearchField` bridge (42)

## Verification

- Screenshot of the panel over a bright window: app names and percentages sit
  on `#616161` or darker.
- `./scripts/check.sh`: 132/132 tests, bundle signed, appcast valid.
- The split is mechanical: `swift build` and the panel screenshot before/after
  are identical apart from the scrim.

## Boundaries

- No change to the glass card on the output section, the HUD, or the hover/press
  feedback.
- Types moved to file scope but stay internal; no public surface changed.
- Do not reintroduce an opaque `windowBackgroundColor`: the scrim is the
  compromise between glass and contrast.

## Maintenance

- New panel surfaces go in their own file; `PanelView.swift` stays the shell.
- If a future macOS material becomes adaptive on its own, the scrim can be
  reduced to one value in `DesignSystem.swift`; the contrast check is a
  screenshot over a white window.
