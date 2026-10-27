import AppKit
import SwiftUI

@MainActor
final class HUDController {
    static let shared = HUDController()

    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    func show(name: String, volume: Float, muted: Bool) {
        let panel = panel ?? makePanel()
        self.panel = panel

        let size = NSSize(width: 220, height: 64)
        let hosting = NSHostingView(rootView: HUDView(name: name, volume: volume, muted: muted))
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        panel.setContentSize(size)

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(
                NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 24)
            )
        }
        panel.orderFrontRegardless()

        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak panel] in panel?.orderOut(nil) }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: item)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        return panel
    }
}

private struct HUDView: View {
    let name: String
    let volume: Float
    let muted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(name)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(Int((volume * 100).rounded()))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.12))
                        Capsule()
                            .fill(muted ? Color.red : Color.accentColor)
                            .frame(width: proxy.size.width * CGFloat(min(max(volume, 0), 2) / 2))
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 220, height: 64)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
