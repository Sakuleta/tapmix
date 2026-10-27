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

    /// Copies and gain-scales one audio buffer, converting channel layouts when needed.
    /// Every output sample is written (zero-filled when there is no input) so stale
    /// hardware buffers can never leak through.
    @inline(__always)
    static func process(
        input: UnsafePointer<Float>,
        inputChannels: Int,
        inputFrames: Int,
        output: UnsafeMutablePointer<Float>,
        outputChannels: Int,
        outputFrames: Int,
        targetGain: Float,
        currentGain: inout Float,
        rampCoefficient: Float
    ) {
        let outputSampleCount = outputFrames * outputChannels
        for index in 0..<outputSampleCount {
            output[index] = 0
        }

        guard inputChannels > 0, outputChannels > 0 else { return }
        let frames = min(inputFrames, outputFrames)
        guard frames > 0 else { return }

        let goal = clampedGain(targetGain)
        var gain = currentGain
        let coefficient = min(max(rampCoefficient, 0), 1)

        for frame in 0..<frames {
            gain += (goal - gain) * coefficient
            let inputBase = frame * inputChannels
            let outputBase = frame * outputChannels

            if inputChannels == outputChannels {
                for channel in 0..<inputChannels {
                    output[outputBase + channel] = clamp(input[inputBase + channel] * gain)
                }
            } else if inputChannels == 1 {
                let sample = clamp(input[inputBase] * gain)
                output[outputBase] = sample
                if outputChannels > 1 {
                    output[outputBase + 1] = sample
                }
            } else if outputChannels == 1 {
                var mixed: Float = 0
                for channel in 0..<inputChannels {
                    mixed += input[inputBase + channel]
                }
                output[outputBase] = clamp((mixed / Float(inputChannels)) * gain)
            } else {
                let copied = min(inputChannels, outputChannels)
                for channel in 0..<copied {
                    output[outputBase + channel] = clamp(input[inputBase + channel] * gain)
                }
            }
        }

        currentGain = gain
    }

    @inline(__always)
    private static func clamp(_ sample: Float) -> Float {
        min(max(sample, -1), 1)
    }
}
