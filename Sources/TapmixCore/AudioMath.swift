import Foundation

/// Real-time safe gain stage used by every process tap.
enum AudioMath {
    static let rampSeconds: Float = 0.02

    /// One-pole coefficient that reaches ~63% of a gain change in `rampSeconds`.
    static func rampCoefficient(sampleRate: Double) -> Float {
        guard sampleRate > 0 else { return 0.002 }
        return 1 - exp(-1 / (Float(sampleRate) * rampSeconds))
    }

    static func clampedGain(_ gain: Float) -> Float {
        min(max(gain, 0), 2)
    }
}
