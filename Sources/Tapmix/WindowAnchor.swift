import AppKit
import SwiftUI

/// Keeps the panel attached to the menu bar.
///
/// `MenuBarExtra` places its window a few points below the bar and can keep a
/// stale origin after the panel changed height while it was closed — the panel
/// then opens detached, one menu-bar height lower. Pinning the top edge to the
/// visible frame whenever the window appears or resizes fixes both cases.
struct MenuBarAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { AnchorView() }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? AnchorView)?.pin()
    }

    final class AnchorView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            pin()
            guard let window else { return }
            for name in [
                NSWindow.didUpdateNotification,
                NSWindow.didBecomeKeyNotification,
                NSWindow.didChangeScreenNotification,
                NSWindow.didResizeNotification
            ] {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(pin),
                    name: name,
                    object: window
                )
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc func pin() {
            guard let window, let screen = window.screen ?? NSScreen.main else { return }
            let top = screen.visibleFrame.maxY
            var frame = window.frame
            guard abs(frame.maxY - top) > 0.5 else { return }
            frame.origin.y = top - frame.height
            window.setFrame(frame, display: true)
        }
    }
}
