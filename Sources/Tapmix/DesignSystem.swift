import SwiftUI

/// Shared visual language for the menu bar panel: a translucent surface, soft
/// cards, and one weight of hover/press feedback.
enum Design {
    static let cardRadius: CGFloat = 11
    static let rowRadius: CGFloat = 10
    static let hairline = Color.primary.opacity(0.07)
    static let hoverDuration: TimeInterval = 0.12
    static let pressDuration: TimeInterval = 0.1
}

/// MenuBarExtra already draws a system material behind the panel; leaving the
/// background clear lets the desktop show through the blur. The gradient adds
/// the top sheen that makes the surface read as glass instead of a flat box.
struct PanelSurface: View {
    var body: some View {
        ZStack {
            Color.clear
            LinearGradient(
                colors: [Color.white.opacity(0.05), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .overlay(alignment: .top) {
            // Specular highlight along the top edge: the cue that separates
            // glass from a flat translucent rectangle.
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.22), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
        }
        .allowsHitTesting(false)
    }
}

struct Hairline: View {
    var inset: CGFloat = 12

    var body: some View {
        Rectangle()
            .fill(Design.hairline)
            .frame(height: 1)
            .padding(.horizontal, inset)
            .accessibilityHidden(true)
    }
}

/// A card that floats on the panel. macOS 26 gets real Liquid Glass; older
/// releases get a material approximation with the same silhouette.
struct PanelCard: ViewModifier {
    var radius: CGFloat = Design.cardRadius

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
                )
        }
    }
}

extension View {
    func panelCard(radius: CGFloat = Design.cardRadius) -> some View {
        modifier(PanelCard(radius: radius))
    }

    /// A soft rounded highlight that follows the pointer. Used on every small
    /// control so the panel reacts before the click lands.
    func hoverHighlight(radius: CGFloat = 6, strength: Double = 0.09) -> some View {
        modifier(HoverHighlight(radius: radius, strength: strength))
    }
}

private struct HoverHighlight: ViewModifier {
    let radius: CGFloat
    let strength: Double
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? strength : 0))
            )
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: Design.hoverDuration), value: hovering)
    }
}

/// Press feedback for icon buttons: a small scale-down that says the click
/// landed, fast enough to feel like part of the pointer.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration)
    }

    private struct PressableLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.94 : 1))
                .opacity(configuration.isPressed ? 0.9 : 1)
                .animation(.easeOut(duration: Design.pressDuration), value: configuration.isPressed)
        }
    }
}
