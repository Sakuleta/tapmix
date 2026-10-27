import CoreAudio
import Darwin
import Foundation

public struct AudioProcess: Hashable {
    public let objectID: AudioObjectID
    public let pid: pid_t
    public let bundleID: String
    public let isPlaying: Bool
    /// Capturing input as well; call apps then run voice processing, which
    /// expects to own its output path.
    public let isCapturing: Bool
    /// Filled from `proc_pidpath`; audio helpers are often not registered apps,
    /// so this is the only way to find their host bundle.
    public let executablePath: String?

    public init(
        objectID: AudioObjectID,
        pid: pid_t,
        bundleID: String,
        isPlaying: Bool,
        isCapturing: Bool = false,
        executablePath: String? = nil
    ) {
        self.objectID = objectID
        self.pid = pid
        self.bundleID = bundleID
        self.isPlaying = isPlaying
        self.isCapturing = isCapturing
        self.executablePath = executablePath
    }
}

public struct AudioDevice: Hashable, Identifiable {
    public let objectID: AudioObjectID
    public let uid: String
    public let name: String

    public var id: String { uid }

    public init(objectID: AudioObjectID, uid: String, name: String) {
        self.objectID = objectID
        self.uid = uid
        self.name = name
    }
}

/// Thin wrappers around the Core Audio HAL properties this app needs.
enum AudioSystem {
    struct PropertyListener {
        let objectID: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    static let systemObject = AudioObjectID(kAudioObjectSystemObject)
    static let elementMain = kAudioObjectPropertyElementMain
    static let scopeGlobal = kAudioObjectPropertyScopeGlobal
    static let scopeOutput = kAudioObjectPropertyScopeOutput

    // MARK: - Process objects

    /// `nil` means the HAL could not answer; an empty array means no process is
    /// using audio right now. The engine treats those differently.
    static func processes() -> [AudioProcess]? {
        guard let objects = objectListOrNil(kAudioHardwarePropertyProcessObjectList) else { return nil }
        return objects.compactMap { objectID in
            guard let pid: UInt32 = readUInt32(objectID, kAudioProcessPropertyPID),
                  let bundleID = readString(objectID, kAudioProcessPropertyBundleID),
                  let running: UInt32 = readUInt32(objectID, kAudioProcessPropertyIsRunningOutput)
            else { return nil }

            let processID = pid_t(pid)
            return AudioProcess(
                objectID: objectID,
                pid: processID,
                bundleID: bundleID,
                isPlaying: running != 0,
                isCapturing: (readUInt32(objectID, kAudioProcessPropertyIsRunningInput) ?? 0) != 0,
                executablePath: executablePath(processID)
            )
        }
    }

    private static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    // MARK: - Output device

    static func defaultOutputDevice() -> AudioDeviceID? {
        let device: AudioDeviceID? = read(systemObject, kAudioHardwarePropertyDefaultOutputDevice)
        guard let device, device != kAudioObjectUnknown else { return nil }
        return device
    }

    /// Bundle IDs of the processes capturing input right now. Device-wide flags
    /// also flip for virtual drivers, recorders and duplex playback, so the
    /// caller still has to look for a call app before ducking anything.
    static func inputBundleIDs() -> Set<String> {
        var listAddress = propertyAddress(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &listAddress, 0, nil, &size) == noErr,
              size > 0
        else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var objects = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(systemObject, &listAddress, 0, nil, &size, &objects) == noErr
        else { return [] }

        var bundleIDs: Set<String> = []
        for object in objects {
            var runningAddress = propertyAddress(kAudioProcessPropertyIsRunningInput)
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(object, &runningAddress, 0, nil, &runningSize, &running) == noErr,
                  running != 0
            else { continue }

            var bundleAddress = propertyAddress(kAudioProcessPropertyBundleID)
            var bundle: CFString = "" as CFString
            var bundleSize = UInt32(MemoryLayout<CFString>.size)
            guard AudioObjectGetPropertyData(object, &bundleAddress, 0, nil, &bundleSize, &bundle) == noErr
            else { continue }

            let identifier = bundle as String
            if !identifier.isEmpty {
                bundleIDs.insert(identifier)
            }
        }
        return bundleIDs
    }

    static func setDefaultOutputDevice(_ device: AudioObjectID) {
        var address = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
        var value = device
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectSetPropertyData(systemObject, &address, 0, nil, size, &value)
    }

    static func deviceUID(_ device: AudioObjectID) -> String? {
        readString(device, kAudioDevicePropertyDeviceUID)
    }

    static func deviceName(_ device: AudioObjectID) -> String? {
        readString(device, kAudioDevicePropertyDeviceNameCFString)
    }

    /// Every device with at least one output stream, excluding our private aggregates.
    static func outputDevices() -> [AudioDevice] {
        objectList(kAudioHardwarePropertyDevices).compactMap { device in
            guard let uid = deviceUID(device),
                  let name = deviceName(device),
                  !name.hasPrefix("Tapmix ")
            else { return nil }

            var address = propertyAddress(kAudioDevicePropertyStreams, scope: scopeOutput)
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
                  size > 0
            else { return nil }

            return AudioDevice(objectID: device, uid: uid, name: name)
        }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
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

    static func addListener(
        _ objectID: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = scopeGlobal,
        handler: @escaping () -> Void
    ) -> PropertyListener? {
        var address = propertyAddress(selector, scope: scope)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        guard AudioObjectAddPropertyListenerBlock(objectID, &address, .main, block) == noErr else {
            return nil
        }
        return PropertyListener(objectID: objectID, address: address, block: block)
    }

    static func removeListener(_ listener: PropertyListener) {
        var address = listener.address
        AudioObjectRemovePropertyListenerBlock(listener.objectID, &address, .main, listener.block)
    }

    static func objectList(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        objectListOrNil(selector) ?? []
    }

    static func objectListOrNil(_ selector: AudioObjectPropertySelector) -> [AudioObjectID]? {
        var address = propertyAddress(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr else {
            return nil
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }

        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &ids) == noErr else {
            return nil
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
