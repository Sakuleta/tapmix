import Foundation

/// Gentle leveler for late-night listening: raises quiet material by a fixed
/// makeup gain and compresses peaks above `threshold`. Stereo-linked; no
/// allocation in `process`.
final class NightModeProcessor {
    static let threshold: Float = 0.125
    static let ratio: Float = 4
    static let makeup: Float = 1.5
    static let minGain: Float = 0.25
    static let maxGain: Float = 4

    private let attackCoefficient: Float
    private let releaseCoefficient: Float
    private var envelope: Float = 0
    private var gain: Float = 1
    private var primed = false

    private(set) var isEnabled = false

    init(sampleRate: Double) {
        let rate = max(sampleRate, 8000)
        attackCoefficient = 1 - exp(-1 / (Float(rate) * 0.005))
        releaseCoefficient = 1 - exp(-1 / (Float(rate) * 0.2))
    }

    func setEnabled(_ enabled: Bool) {
        if enabled, !isEnabled {
            primed = false
            gain = 1
        }
        isEnabled = enabled
    }

    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        guard isEnabled else { return (left, right) }

        let peak = max(abs(left), abs(right))
        if !primed {
            envelope = peak
            primed = true
        } else if peak > envelope {
            envelope += (peak - envelope) * attackCoefficient
        } else {
            envelope += (peak - envelope) * releaseCoefficient
        }

        let level = max(envelope, 0.0001)
        let compressed = level > Self.threshold
            ? Self.threshold + (level - Self.threshold) / Self.ratio
            : level
        let target = min(max((compressed * Self.makeup) / level, Self.minGain), Self.maxGain)

        if target < gain {
            gain += (target - gain) * attackCoefficient
        } else {
            gain += (target - gain) * releaseCoefficient
        }

        return (left * gain, right * gain)
    }
}
