import AudioToolbox
import Foundation

enum AudioUnitHostError: LocalizedError {
    case missingComponent
    case setup(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingComponent:
            return "The Audio Unit is not installed."
        case let .setup(step, status):
            return "Audio Unit \(step) failed (\(status))."
        }
    }
}

/// Hosts one AUv2 effect inside the tap's render callback, using the Audio Unit
/// render-callback API (no AVAudioEngine or AUGraph).
final class AudioUnitHost {
    static let maximumFrames = 4_096

    private let unit: AudioUnit
    private let inputLeft: UnsafeMutablePointer<Float>
    private let inputRight: UnsafeMutablePointer<Float>
    private let outputLeft: UnsafeMutablePointer<Float>
    private let outputRight: UnsafeMutablePointer<Float>
    private let outputList: UnsafeMutableAudioBufferListPointer
    private var sampleTime: Float64 = 0

    init(selection: AudioUnitSelection, sampleRate: Double) throws {
        var description = selection.componentDescription
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw AudioUnitHostError.missingComponent
        }

        var instance: AudioComponentInstance?
        let createStatus = AudioComponentInstanceNew(component, &instance)
        guard createStatus == noErr, let instance else {
            throw AudioUnitHostError.setup("creation", createStatus)
        }

        var format = AudioStreamBasicDescription(
            mSampleRate: max(sampleRate, 8_000),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        let formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

        var status = AudioUnitSetProperty(
            instance,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            0,
            &format,
            formatSize
        )
        guard status == noErr else {
            AudioComponentInstanceDispose(instance)
            throw AudioUnitHostError.setup("input format", status)
        }

        status = AudioUnitSetProperty(
            instance,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            0,
            &format,
            formatSize
        )
        guard status == noErr else {
            AudioComponentInstanceDispose(instance)
            throw AudioUnitHostError.setup("output format", status)
        }

        var maximumFrames = UInt32(Self.maximumFrames)
        status = AudioUnitSetProperty(
            instance,
            kAudioUnitProperty_MaximumFramesPerSlice,
            kAudioUnitScope_Global,
            0,
            &maximumFrames,
            UInt32(MemoryLayout<UInt32>.size)
        )
        guard status == noErr else {
            AudioComponentInstanceDispose(instance)
            throw AudioUnitHostError.setup("frame limit", status)
        }

        unit = instance
        inputLeft = UnsafeMutablePointer<Float>.allocate(capacity: Self.maximumFrames)
        inputRight = UnsafeMutablePointer<Float>.allocate(capacity: Self.maximumFrames)
        outputLeft = UnsafeMutablePointer<Float>.allocate(capacity: Self.maximumFrames)
        outputRight = UnsafeMutablePointer<Float>.allocate(capacity: Self.maximumFrames)
        inputLeft.initialize(repeating: 0, count: Self.maximumFrames)
        inputRight.initialize(repeating: 0, count: Self.maximumFrames)
        outputLeft.initialize(repeating: 0, count: Self.maximumFrames)
        outputRight.initialize(repeating: 0, count: Self.maximumFrames)
        outputList = AudioBufferList.allocate(maximumBuffers: 2)

        var callback = AURenderCallbackStruct(
            inputProc: audioUnitInputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        status = AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Input,
            0,
            &callback,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        guard status == noErr else {
            freeBuffers()
            AudioComponentInstanceDispose(instance)
            throw AudioUnitHostError.setup("render callback", status)
        }

        status = AudioUnitInitialize(unit)
        guard status == noErr else {
            freeBuffers()
            AudioComponentInstanceDispose(instance)
            throw AudioUnitHostError.setup("initialization", status)
        }
    }

    deinit {
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
        freeBuffers()
    }

    /// Called on the realtime thread after the tap has rendered its output.
    /// The list may be interleaved or planar; channels past the first two are
    /// left untouched. The output is clamped so an effect that boosts cannot
    /// exceed full scale on the device.
    func process(bufferList: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)

        var leftBase: UnsafeMutablePointer<Float>?
        var rightBase: UnsafeMutablePointer<Float>?
        var leftStride = 1
        var rightStride = 1
        var globalChannel = 0
        var frames = Self.maximumFrames

        for buffer in buffers {
            let channels = max(1, Int(buffer.mNumberChannels))
            frames = min(frames, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels))
            if let data = buffer.mData?.assumingMemoryBound(to: Float.self) {
                if globalChannel == 0 {
                    leftBase = data
                    leftStride = channels
                }
                if globalChannel <= 1, globalChannel + channels > 1 {
                    rightBase = data.advanced(by: 1 - globalChannel)
                    rightStride = channels
                }
            }
            globalChannel += channels
        }

        guard let leftBase, let rightBase, globalChannel >= 2, frames > 0 else { return }

        for frame in 0 ..< frames {
            inputLeft[frame] = leftBase[frame * leftStride]
            inputRight[frame] = rightBase[frame * rightStride]
            outputLeft[frame] = inputLeft[frame]
            outputRight[frame] = inputRight[frame]
        }

        let byteSize = UInt32(frames * MemoryLayout<Float>.size)
        outputList[0] = AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: byteSize,
            mData: outputLeft
        )
        outputList[1] = AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: byteSize,
            mData: outputRight
        )

        var flags = AudioUnitRenderActionFlags()
        var timestamp = AudioTimeStamp()
        timestamp.mSampleTime = sampleTime
        timestamp.mFlags = .sampleTimeValid
        let status = AudioUnitRender(
            unit,
            &flags,
            &timestamp,
            0,
            UInt32(frames),
            outputList.unsafeMutablePointer
        )
        sampleTime += Double(frames)
        guard status == noErr else { return }

        for frame in 0 ..< frames {
            leftBase[frame * leftStride] = min(max(outputLeft[frame], -1), 1)
            rightBase[frame * rightStride] = min(max(outputRight[frame], -1), 1)
        }
    }

    fileprivate func fillInput(
        _ ioData: UnsafeMutablePointer<AudioBufferList>?,
        frames: Int
    ) -> OSStatus {
        guard let ioData, frames <= Self.maximumFrames else { return noErr }
        let buffers = UnsafeMutableAudioBufferListPointer(ioData)

        if buffers.count >= 2 {
            buffers[0].mData?.assumingMemoryBound(to: Float.self)
                .update(from: inputLeft, count: frames)
            buffers[1].mData?.assumingMemoryBound(to: Float.self)
                .update(from: inputRight, count: frames)
        } else if buffers.count == 1,
                  let data = buffers[0].mData?.assumingMemoryBound(to: Float.self) {
            for frame in 0 ..< frames {
                data[frame * 2] = inputLeft[frame]
                data[frame * 2 + 1] = inputRight[frame]
            }
        }
        return noErr
    }

    private func freeBuffers() {
        inputLeft.deinitialize(count: Self.maximumFrames)
        inputLeft.deallocate()
        inputRight.deinitialize(count: Self.maximumFrames)
        inputRight.deallocate()
        outputLeft.deinitialize(count: Self.maximumFrames)
        outputLeft.deallocate()
        outputRight.deinitialize(count: Self.maximumFrames)
        outputRight.deallocate()
        free(outputList.unsafeMutablePointer)
    }
}

private func audioUnitInputCallback(
    _ refCon: UnsafeMutableRawPointer,
    _ actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    _ timestamp: UnsafePointer<AudioTimeStamp>,
    _ busNumber: UInt32,
    _ frames: UInt32,
    _ ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let host = Unmanaged<AudioUnitHost>.fromOpaque(refCon).takeUnretainedValue()
    return host.fillInput(ioData, frames: Int(frames))
}
