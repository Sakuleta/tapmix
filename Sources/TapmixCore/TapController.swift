import AudioToolbox
import CoreAudio
import Foundation
import os

enum TapError: LocalizedError {
    case coreAudio(String, OSStatus)
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case let .coreAudio(step, status):
            return "\(step) failed (Core Audio error \(status))."
        case let .unsupportedFormat(detail):
            return "The tap format is not supported: \(detail)"
        }
    }
}

/// Captures one process through a private Core Audio tap and plays it back through
/// a private aggregate device with a smoothed gain stage.
///
/// The tap uses `.mutedWhenTapped`, so the app's direct output is suppressed only
/// while this tap is being read. Destroying the controller restores normal audio.
final class TapController: TapControlling {
    let processObjectID: AudioObjectID
    let bundleID: String
    let createdAt = Date()

    /// Written on the real-time thread, read from the UI for the permission health check.
    private(set) var callbackCount: UInt64 = 0

    /// Peak since the last UI read; aligned Float access is atomic on Apple silicon.
    private var peakLevel: Float = 0
    private(set) var running = false

    var isRecording: Bool { recorder?.isActive ?? false }

    private let outputDeviceUID: String
    private let log = Logger(subsystem: "com.mardinli.tapmix", category: "tap")
    private let queue = DispatchQueue(label: "com.mardinli.tapmix.tap", qos: .userInteractive)

    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioObjectID = 0
    private var ioProcID: AudioDeviceIOProcID?
    private var ramp: Float = 0.002
    private var limiter: LookaheadLimiter?
    private var eqProcessor: EQProcessor?
    private var pendingEQ = EQSettings()
    private var nightModeProcessor: NightModeProcessor?
    private var pendingNightMode = false
    private var balance: Float = 0
    private var mono = false
    private var sampleRate: Double = 48_000
    private var recorder: TapRecorder?
    private var pendingAudioUnit: AudioUnitSelection?
    private var audioUnitHost: AudioUnitHost?

    // Realtime gain state. Aligned Float reads/writes are atomic on Apple silicon.
    private var targetGain: Float = 1
    private var currentGain: Float = 0

    init(processObjectID: AudioObjectID, bundleID: String, outputDeviceUID: String) {
        self.processObjectID = processObjectID
        self.bundleID = bundleID
        self.outputDeviceUID = outputDeviceUID
    }

    deinit {
        stop()
    }

    func setGain(_ gain: Float) {
        targetGain = AudioMath.clampedGain(gain)
    }

    func setEQ(_ settings: EQSettings) {
        pendingEQ = settings
        eqProcessor?.update(settings)
    }

    func setNightMode(_ enabled: Bool) {
        pendingNightMode = enabled
        nightModeProcessor?.setEnabled(enabled)
    }

    func setBalance(_ balance: Float) {
        self.balance = min(max(balance, -1), 1)
    }

    func setMono(_ enabled: Bool) {
        mono = enabled
    }

    func setAudioUnit(_ selection: AudioUnitSelection?) {
        guard selection != pendingAudioUnit else { return }
        pendingAudioUnit = selection
        swapAudioUnit()
    }

    private func swapAudioUnit() {
        let host = pendingAudioUnit.flatMap { selection -> AudioUnitHost? in
            do {
                let host = try AudioUnitHost(selection: selection, sampleRate: sampleRate)
                log.info("Audio Unit ready subtype=\(selection.componentSubType) rate=\(Int(self.sampleRate))")
                return host
            } catch {
                log.error("Audio Unit unavailable: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }

        // The IO proc runs on `queue`, so swapping there lands between render
        // callbacks and releases the old host with no thread using it.
        queue.sync {
            audioUnitHost = host
        }
    }

    func startRecording(to url: URL) throws {
        // File creation stays off the audio queue; publishing the recorder lands
        // between callbacks so the render thread never sees a half swap.
        let recorder = try TapRecorder(url: url, sampleRate: sampleRate)
        queue.sync {
            self.recorder?.stop()
            self.recorder = recorder
        }
    }

    func stopRecording() {
        queue.sync {
            recorder?.stop()
            recorder = nil
        }
    }

    func takePeakLevel() -> Float {
        let peak = peakLevel
        peakLevel = 0
        return peak
    }

    func start() throws {
        guard !running else { return }

        let description = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = CATapMuteBehavior.mutedWhenTapped
        description.name = "Tapmix \(bundleID)"

        var newTapID: AudioObjectID = 0
        var status = AudioHardwareCreateProcessTap(description, &newTapID)
        guard status == noErr, newTapID != kAudioObjectUnknown else {
            throw TapError.coreAudio("Creating the process tap", status)
        }

        if let format = processTapFormat(newTapID) {
            let supported = format.mFormatID == kAudioFormatLinearPCM
                && (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0
                && (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
                && format.mBitsPerChannel == 32
                && format.mChannelsPerFrame <= 2
            guard supported else {
                AudioHardwareDestroyProcessTap(newTapID)
                throw TapError.unsupportedFormat(
                    "id=\(format.mFormatID) flags=\(format.mFormatFlags) bits=\(format.mBitsPerChannel) channels=\(format.mChannelsPerFrame)"
                )
            }
        } else {
            log.warning("Could not read the tap format; assuming interleaved Float32.")
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Tapmix \(bundleID)",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceClockDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputDeviceUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: description.uuid.uuidString]
            ]
        ]

        var newAggregateID: AudioObjectID = 0
        status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateID)
        guard status == noErr, newAggregateID != kAudioObjectUnknown else {
            AudioHardwareDestroyProcessTap(newTapID)
            throw TapError.coreAudio("Creating the private output device", status)
        }

        let sampleRate = nominalSampleRate(newAggregateID)
        self.sampleRate = sampleRate
        ramp = AudioMath.rampCoefficient(sampleRate: sampleRate)
        limiter = LookaheadLimiter(sampleRate: sampleRate)
        let eq = EQProcessor(sampleRate: sampleRate)
        eq.update(pendingEQ)
        eqProcessor = eq
        let night = NightModeProcessor(sampleRate: sampleRate)
        night.setEnabled(pendingNightMode)
        nightModeProcessor = night
        swapAudioUnit()
        var newProcID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&newProcID, newAggregateID, queue) { [weak self] _, input, _, output, _ in
            guard let self else {
                TapController.zero(output)
                return
            }
            self.render(input, output)
        }

        guard status == noErr, let newProcID else {
            AudioHardwareDestroyAggregateDevice(newAggregateID)
            AudioHardwareDestroyProcessTap(newTapID)
            throw TapError.coreAudio("Creating the audio callback", status)
        }

        disableHardwareInputs(aggregateID: newAggregateID, procID: newProcID)

        status = AudioDeviceStart(newAggregateID, newProcID)
        guard status == noErr else {
            AudioDeviceDestroyIOProcID(newAggregateID, newProcID)
            AudioHardwareDestroyAggregateDevice(newAggregateID)
            AudioHardwareDestroyProcessTap(newTapID)
            throw TapError.coreAudio("Starting the audio device", status)
        }

        tapID = newTapID
        aggregateID = newAggregateID
        ioProcID = newProcID
        running = true

        // Fade in, and pick up the gain that was requested before the tap existed.
        currentGain = 0
        log.info("Tap started bundle=\(self.bundleID, privacy: .public) process=\(self.processObjectID) rate=\(Int(sampleRate)) inputs=\(self.streamCount(newAggregateID, scope: kAudioObjectPropertyScopeInput)) outputs=\(self.streamCount(newAggregateID, scope: kAudioObjectPropertyScopeOutput))")
    }

    func stop() {
        guard running || aggregateID != 0 || tapID != 0 else { return }

        // Stop the callback before freeing anything it can still reach, then
        // release the host and recorder on the tap queue so the last reference
        // cannot drop on the realtime thread.
        if aggregateID != 0, let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil
        running = false

        queue.sync {
            recorder?.stop()
            recorder = nil
            audioUnitHost = nil
        }

        if aggregateID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = 0
        }

        if tapID != 0 {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = 0
        }

        log.debug("Tap stopped for \(self.bundleID, privacy: .public)")
    }

    // MARK: - Realtime callback

    private func render(
        _ inputBufferList: UnsafePointer<AudioBufferList>,
        _ outputBufferList: UnsafeMutablePointer<AudioBufferList>
    ) {
        callbackCount &+= 1

        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputBufferList))
        guard let tapBuffer = inputs.last,
              let plan = TapRenderPlan.make(
                  inputBufferCount: inputs.count,
                  tapInputChannels: Int(tapBuffer.mNumberChannels)
              )
        else {
            TapController.zero(outputBufferList)
            return
        }

        let peak = TapRender.render(
            input: inputBufferList,
            output: outputBufferList,
            plan: plan,
            targetGain: targetGain,
            currentGain: &currentGain,
            rampCoefficient: ramp,
            eq: eqProcessor,
            nightMode: nightModeProcessor,
            balance: balance,
            mono: mono,
            limiter: limiter
        )
        peakLevel = max(peakLevel, peak)
        audioUnitHost?.process(bufferList: outputBufferList)
        recorder?.write(bufferList: outputBufferList)
    }

    private static func zero(_ bufferList: UnsafeMutablePointer<AudioBufferList>) {
        for buffer in UnsafeMutableAudioBufferListPointer(bufferList) {
            if let data = buffer.mData {
                memset(data, 0, Int(buffer.mDataByteSize))
            }
        }
    }

    // MARK: - Core Audio details

    private func processTapFormat(_ tapID: AudioObjectID) -> AudioStreamBasicDescription? {
        var address = AudioSystem.propertyAddress(kAudioTapPropertyFormat)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format) == noErr else {
            return nil
        }
        return format
    }

    private func nominalSampleRate(_ deviceID: AudioObjectID) -> Double {
        var address = AudioSystem.propertyAddress(kAudioDevicePropertyNominalSampleRate, scope: AudioSystem.scopeGlobal)
        var rate: Float64 = 48_000
        var size = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &rate)
        return status == noErr && rate > 0 ? rate : 48_000
    }

    /// Marks the aggregate's hardware input streams as unused. Without this, a duplex
    /// interface (USB audio device with a microphone) would be treated as recording and
    /// could trigger a microphone permission prompt.
    private func disableHardwareInputs(aggregateID: AudioObjectID, procID: AudioDeviceIOProcID) {
        let inputCount = streamCount(aggregateID, scope: kAudioObjectPropertyScopeInput)
        let outputCount = streamCount(aggregateID, scope: kAudioObjectPropertyScopeOutput)
        guard inputCount > 0, outputCount > 0, inputCount > outputCount else { return }

        let headerSize = MemoryLayout<UnsafeMutableRawPointer>.size + MemoryLayout<UInt32>.size
        let totalSize = headerSize + inputCount * MemoryLayout<UInt32>.size
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: totalSize,
            alignment: MemoryLayout<UnsafeMutableRawPointer>.alignment
        )
        defer { raw.deallocate() }

        raw.storeBytes(of: unsafeBitCast(procID, to: UnsafeMutableRawPointer.self), as: UnsafeMutableRawPointer.self)
        raw.storeBytes(of: UInt32(inputCount), toByteOffset: MemoryLayout<UnsafeMutableRawPointer>.size, as: UInt32.self)
        for index in 0..<inputCount {
            let used: UInt32 = index >= inputCount - outputCount ? 1 : 0
            raw.storeBytes(of: used, toByteOffset: headerSize + index * MemoryLayout<UInt32>.size, as: UInt32.self)
        }

        var address = AudioSystem.propertyAddress(
            kAudioDevicePropertyIOProcStreamUsage,
            scope: kAudioObjectPropertyScopeInput
        )
        let status = AudioObjectSetPropertyData(aggregateID, &address, 0, nil, UInt32(totalSize), raw)
        if status != noErr {
            log.debug("Could not disable hardware input streams: \(status)")
        }
    }

    private func streamCount(_ deviceID: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioSystem.propertyAddress(kAudioDevicePropertyStreams, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else {
            return 0
        }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }
}
