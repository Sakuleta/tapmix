import CoreAudio
import Foundation

public struct AudioProcess: Hashable {
    public let objectID: AudioObjectID
    public let pid: pid_t
    public let bundleID: String
    public let isPlaying: Bool

    public init(objectID: AudioObjectID, pid: pid_t, bundleID: String, isPlaying: Bool) {
        self.objectID = objectID
        self.pid = pid
        self.bundleID = bundleID
        self.isPlaying = isPlaying
    }
}

/// Thin wrappers around the Core Audio HAL properties this app needs.
enum AudioSystem {
    static let systemObject = AudioObjectID(kAudioObjectSystemObject)
    static let elementMain = kAudioObjectPropertyElementMain
    static let scopeGlobal = kAudioObjectPropertyScopeGlobal
    static let scopeOutput = kAudioObjectPropertyScopeOutput

    // MARK: - Process objects

    static func processes() -> [AudioProcess] {
        objectList(kAudioHardwarePropertyProcessObjectList).compactMap { objectID in
            guard let pid: UInt32 = readUInt32(objectID, kAudioProcessPropertyPID),
                  let bundleID = readString(objectID, kAudioProcessPropertyBundleID),
                  let running: UInt32 = readUInt32(objectID, kAudioProcessPropertyIsRunningOutput)
            else { return nil }

            return AudioProcess(
                objectID: objectID,
                pid: pid_t(pid),
                bundleID: bundleID,
                isPlaying: running != 0
            )
        }
    }

    // MARK: - Output device

    static func defaultOutputDevice() -> AudioDeviceID? {
        let device: AudioDeviceID? = read(systemObject, kAudioHardwarePropertyDefaultOutputDevice)
        guard let device, device != kAudioObjectUnknown else { return nil }
        return device
    }

    static func deviceUID(_ device: AudioObjectID) -> String? {
        readString(device, kAudioDevicePropertyDeviceUID)
    }

    static func deviceName(_ device: AudioObjectID) -> String? {
        readString(device, kAudioDevicePropertyDeviceNameCFString)
    }

    static func outputVolume(_ device: AudioObjectID) -> Float? {
        if let value: Float = read(device, kAudioDevicePropertyVolumeScalar, scope: scopeOutput) {
            return value
        }
        var channelValues: [Float] = []
        for channel: UInt32 in [1, 2] {
            if let value = readScalar(device, element: channel) {
                channelValues.append(value)
            }
        }
        guard !channelValues.isEmpty else { return nil }
        return channelValues.reduce(0, +) / Float(channelValues.count)
    }

    static func setOutputVolume(_ device: AudioObjectID, _ volume: Float) {
        let value = min(max(volume, 0), 1)
        if setScalar(device, element: elementMain, value: value) {
            return
        }
        _ = setScalar(device, element: 1, value: value)
        _ = setScalar(device, element: 2, value: value)
    }

    /// Main-element mute wins; otherwise the device counts as muted only when
    /// every channel reports muted. `nil` means the device has no mute property.
    static func combinedMute(main: Bool?, channels: [Bool]) -> Bool? {
        if let main { return main }
        guard !channels.isEmpty else { return nil }
        return channels.allSatisfy { $0 }
    }

    static func outputMuted(_ device: AudioObjectID) -> Bool? {
        let mainValue: UInt32? = read(device, kAudioDevicePropertyMute, scope: scopeOutput)
        let main = mainValue.map { $0 != 0 }
        var channels: [Bool] = []
        for channel: UInt32 in [1, 2] {
            if let value: UInt32 = read(
                device,
                kAudioDevicePropertyMute,
                scope: scopeOutput,
                element: channel
            ) {
                channels.append(value != 0)
            }
        }
        return combinedMute(main: main, channels: channels)
    }

    static func setOutputMuted(_ device: AudioObjectID, _ muted: Bool) {
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)

        var mainAddress = propertyAddress(kAudioDevicePropertyMute, scope: scopeOutput)
        if AudioObjectSetPropertyData(device, &mainAddress, 0, nil, size, &value) == noErr {
            return
        }

        for channel: UInt32 in [1, 2] {
            var address = propertyAddress(
                kAudioDevicePropertyMute,
                scope: scopeOutput,
                element: channel
            )
            _ = AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
        }
    }

    // MARK: - Property plumbing

    static func propertyAddress(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = scopeGlobal,
        element: AudioObjectPropertyElement = elementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func objectList(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = propertyAddress(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr else {
            return []
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }

        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return ids
    }

    static func read<T>(
        _ objectID: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = scopeGlobal,
        element: AudioObjectPropertyElement = elementMain
    ) -> T? {
        var address = propertyAddress(selector, scope: scope, element: element)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer) == noErr else {
            return nil
        }
        return pointer.pointee
    }

    static func readUInt32(
        _ objectID: AudioObjectID,
        _ selector: AudioObjectPropertySelector
    ) -> UInt32? {
        read(objectID, selector)
    }

    static func readString(
        _ objectID: AudioObjectID,
        _ selector: AudioObjectPropertySelector
    ) -> String? {
        var address = propertyAddress(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString?
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let string = value as String? else { return nil }
        return string
    }

    private static func readScalar(_ device: AudioObjectID, element: UInt32) -> Float? {
        var address = propertyAddress(kAudioDevicePropertyVolumeScalar, scope: scopeOutput, element: element)
        var value: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    private static func setScalar(_ device: AudioObjectID, element: UInt32, value: Float) -> Bool {
        var address = propertyAddress(kAudioDevicePropertyVolumeScalar, scope: scopeOutput, element: element)
        var value = value
        let size = UInt32(MemoryLayout<Float>.size)
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr
    }
}
