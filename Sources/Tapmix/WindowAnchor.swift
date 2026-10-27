import AppKit
import SwiftUI

/// Keeps the panel attached to the menu bar.
///
/// `MenuBarExtra` places its window just under the bar, but can keep a stale
/// frame when the panel's height changed while it was closed: the panel then
/// opens detached, one menu-bar height lower, with square corners because the
/// content is drawn smaller than the window. This view enforces the size the
/// SwiftUI root asks for and pins the top edge to the visible frame on every
/// show or resize.
struct MenuBarAnchor: NSViewRepresentable {
    let size: CGSize

    func makeNSView(context: Context) -> NSView { AnchorView() }

    func updateNSView(_ view: NSView, context: Context) {
        guard let anchor = view as? AnchorView else { return }
        anchor.target = size
        anchor.pin()
    }

    final class AnchorView: NSView {
        var target: CGSize = .zero

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            pin()
            guard let window else { return }
            for name in [
                NSWindow.didUpdateNotification,
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResizeNotification,
                NSWindow.didChangeScreenNotification
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

            if target.width > 0, target.height > 0 {
                let current = window.contentView?.bounds.size ?? .zero
                if abs(current.height - target.height) > 2 || abs(current.width - target.width) > 2 {
                    window.setContentSize(target)
                }
            }

            let top = screen.visibleFrame.maxY
            var frame = window.frame
            guard abs(frame.maxY - top) > 0.5 else { return }
            frame.origin.y = top - frame.height
            window.setFrame(frame, display: true)
        }
    }
}
