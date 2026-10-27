import AudioToolbox
import CoreAudio
import Foundation

/// Where the tap's buffer lives inside the aggregate's input list.
struct TapRenderPlan: Equatable {
    let tapInputIndex: Int
    let tapInputChannels: Int

    static func make(inputBufferCount: Int, tapInputChannels: Int) -> TapRenderPlan? {
        guard inputBufferCount > 0, (1...2).contains(tapInputChannels) else { return nil }
        return TapRenderPlan(
            tapInputIndex: inputBufferCount - 1,
            tapInputChannels: tapInputChannels
        )
    }
}

/// Frame-major renderer for one tap into one output buffer list.
///
/// Output channel 0 is left and channel 1 is right; a mono output gets the
/// left/right mixdown and any extra channels stay silent. The gain ramp advances
/// once per frame, so planar outputs always share the same gain.
enum TapRender {
    static func render(
        input: UnsafePointer<AudioBufferList>,
        output: UnsafeMutablePointer<AudioBufferList>,
        plan: TapRenderPlan,
        targetGain: Float,
        currentGain: inout Float,
        rampCoefficient: Float
    ) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)

        for buffer in outputs {
            if let data = buffer.mData {
                memset(data, 0, Int(buffer.mDataByteSize))
            }
        }

        guard plan.tapInputIndex >= 0, plan.tapInputIndex < inputs.count,
              let tapData = inputs[plan.tapInputIndex].mData
        else { return }

        let tapChannels = max(1, min(plan.tapInputChannels, 2))
        var frames = Int(inputs[plan.tapInputIndex].mDataByteSize)
            / (MemoryLayout<Float>.size * tapChannels)
        var totalOutputChannels = 0

        for buffer in outputs {
            let channels = max(1, Int(buffer.mNumberChannels))
            totalOutputChannels += channels
            let bufferFrames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
            frames = min(frames, bufferFrames)
        }

        guard frames > 0, totalOutputChannels > 0 else { return }

        let samples = tapData.assumingMemoryBound(to: Float.self)
        let goal = AudioMath.clampedGain(targetGain)
        let coefficient = min(max(rampCoefficient, 0), 1)
        var gain = currentGain

        for frame in 0..<frames {
            gain += (goal - gain) * coefficient

            let tapBase = frame * tapChannels
            let left = samples[tapBase]
            let right = tapChannels == 1 ? left : samples[tapBase + 1]

            var channelOffset = 0
            for buffer in outputs {
                let channels = max(1, Int(buffer.mNumberChannels))
                if let data = buffer.mData {
                    writeFrame(
                        left: left,
                        right: right,
                        into: data.assumingMemoryBound(to: Float.self).advanced(by: frame * channels),
                        channels: channels,
                        globalChannelOffset: channelOffset,
                        totalOutputChannels: totalOutputChannels,
                        gain: gain
                    )
                }
                channelOffset += channels
            }
        }

        currentGain = gain
    }

    @inline(__always)
    static func writeFrame(
        left: Float,
        right: Float,
        into output: UnsafeMutablePointer<Float>,
        channels: Int,
        globalChannelOffset: Int,
        totalOutputChannels: Int,
        gain: Float
    ) {
        if totalOutputChannels == 1 {
            output[0] = clamp(((left + right) * 0.5) * gain)
            return
        }

        for channel in 0..<channels {
            let globalChannel = globalChannelOffset + channel
            let sample: Float
            if globalChannel == 0 {
                sample = left * gain
            } else if globalChannel == 1 {
                sample = right * gain
            } else {
                sample = 0
            }
            output[channel] = clamp(sample)
        }
    }

    @inline(__always)
    private static func clamp(_ sample: Float) -> Float {
        min(max(sample, -1), 1)
    }
}
