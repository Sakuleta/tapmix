import AudioToolbox
import Foundation

public struct AudioUnitSelection: Codable, Equatable, Sendable {
    public let componentType: UInt32
    public let componentSubType: UInt32
    public let componentManufacturer: UInt32

    public init(
        componentType: UInt32 = UInt32(kAudioUnitType_Effect),
        componentSubType: UInt32,
        componentManufacturer: UInt32
    ) {
        self.componentType = componentType
        self.componentSubType = componentSubType
        self.componentManufacturer = componentManufacturer
    }

    public var componentDescription: AudioComponentDescription {
        AudioComponentDescription(
            componentType: componentType,
            componentSubType: componentSubType,
            componentManufacturer: componentManufacturer,
            componentFlags: 0,
            componentFlagsMask: 0
        )
    }
}

public struct AudioUnitInfo: Identifiable, Equatable, Sendable {
    public let name: String
    public let selection: AudioUnitSelection

    public var id: AudioUnitSelectionKey { AudioUnitSelectionKey(selection) }
    public init(name: String, selection: AudioUnitSelection) {
        self.name = name
        self.selection = selection
    }
}

public struct AudioUnitSelectionKey: Hashable, Sendable {
    public let type: UInt32
    public let subType: UInt32
    public let manufacturer: UInt32

    public init(_ selection: AudioUnitSelection) {
        type = selection.componentType
        subType = selection.componentSubType
        manufacturer = selection.componentManufacturer
    }
}

public enum AudioUnitCatalog {
    public static func effects() -> [AudioUnitInfo] {
        var search = AudioComponentDescription(
            componentType: UInt32(kAudioUnitType_Effect),
            componentSubType: 0,
            componentManufacturer: 0,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        var results: [AudioUnitInfo] = []
        var seen = Set<AudioUnitSelectionKey>()
        var component = AudioComponentFindNext(nil, &search)

        while let current = component {
            var description = AudioComponentDescription()
            var rawName: Unmanaged<CFString>?
            if AudioComponentGetDescription(current, &description) == noErr,
               AudioComponentCopyName(current, &rawName) == noErr,
               let rawName {
                let name = rawName.takeRetainedValue() as String
                if !name.isEmpty {
                    let selection = AudioUnitSelection(
                        componentType: description.componentType,
                        componentSubType: description.componentSubType,
                        componentManufacturer: description.componentManufacturer
                    )
                    let key = AudioUnitSelectionKey(selection)
                    if seen.insert(key).inserted {
                        results.append(AudioUnitInfo(name: name, selection: selection))
                    }
                }
            }
            component = AudioComponentFindNext(current, &search)
        }

        return results.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
