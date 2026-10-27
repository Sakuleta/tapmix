import Foundation

/// Stereo-linked peak limiter with a short lookahead delay.
///
/// The delay gives the gain envelope time to react before a loud frame reaches
/// the output, so boosts up to 4x stay below the ceiling instead of clipping.
/// Instances are created on the setup path and only touched from one render
/// callback; `process` performs no allocation.
final class LookaheadLimiter {
    static let ceiling: Float = 0.98

    private var delayLeft: [Float]
    private var delayRight: [Float]
    private var writeIndex = 0
    private var gain: Float = 1
    private let releaseCoefficient: Float

    init(
        sampleRate: Double,
        lookaheadSeconds: Double = 0.005,
        releaseSeconds: Double = 0.15
    ) {
        let frames = max(1, Int(sampleRate * lookaheadSeconds))
        delayLeft = [Float](repeating: 0, count: frames)
        delayRight = [Float](repeating: 0, count: frames)

        if sampleRate > 0, releaseSeconds > 0 {
            releaseCoefficient = 1 - exp(-1 / (Float(sampleRate) * Float(releaseSeconds)))
        } else {
            releaseCoefficient = 1
        }
    }

    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        let outputLeft = delayLeft[writeIndex]
        let outputRight = delayRight[writeIndex]
        delayLeft[writeIndex] = left
        delayRight[writeIndex] = right

        writeIndex += 1
        if writeIndex == delayLeft.count {
            writeIndex = 0
        }

        let peak = max(abs(left), abs(right))
        let target: Float = peak > Self.ceiling ? Self.ceiling / peak : 1
        if target < gain {
            gain = target
        } else {
            gain += (target - gain) * releaseCoefficient
        }

        return (outputLeft * gain, outputRight * gain)
    }
}
