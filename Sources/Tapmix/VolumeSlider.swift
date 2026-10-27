import SwiftUI

/// A slim slider that stays readable on the glass panel. The system `Slider`
/// draws its unfilled track with a colour that disappears on a translucent
/// light surface, so the mixer draws its own track, fill and thumb.
struct VolumeSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var tint: Color = .accentColor
    let label: String
    let valueDescription: String
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var dragging = false

    private let trackHeight: CGFloat = 4
    private let thumbSize: CGFloat = 12
    private let hitHeight: CGFloat = 18

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let travel = max(proxy.size.width - thumbSize, 1)
            let offset = CGFloat(fraction) * travel

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.16))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(tint)
                    .frame(width: offset + thumbSize / 2, height: trackHeight)

                Circle()
                    .fill(.white)
                    .overlay(Circle().strokeBorder(.black.opacity(0.14)))
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                    .offset(x: offset)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !dragging {
                            dragging = true
                            onEditingChanged(true)
                        }
                        let position = min(max(drag.location.x - thumbSize / 2, 0), travel)
                        let span = range.upperBound - range.lowerBound
                        let next = range.lowerBound + Double(position / travel) * span
                        if next != value {
                            value = next
                        }
                    }
                    .onEnded { _ in
                        dragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: hitHeight)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(valueDescription)
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment:
                value = min(value + step, range.upperBound)
            case .decrement:
                value = max(value - step, range.lowerBound)
            @unknown default:
                break
            }
        }
    }
}
