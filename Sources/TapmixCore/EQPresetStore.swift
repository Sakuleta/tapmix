import Foundation

public struct SavedEQPreset: Codable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var settings: EQSettings

    public init(id: UUID = UUID(), name: String, settings: EQSettings) {
        self.id = id
        self.name = name
        self.settings = settings
    }
}

/// User-created EQ presets, stored next to the levels so the same correction can
/// be applied to any app later.
public final class EQPresetStore {
    private static let key = "com.mardinli.tapmix.eqPresets"
    private static let limit = 20

    private let section: DefaultsSection<[SavedEQPreset]>
    public private(set) var presets: [SavedEQPreset]

    public init(defaults: UserDefaults = .standard) {
        section = DefaultsSection(defaults: defaults, key: Self.key)
        presets = section.load(default: [])
    }

    public func save(name: String, settings: EQSettings) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Preset \(presets.count + 1)" : trimmed

        if let index = presets.firstIndex(where: {
            $0.name.caseInsensitiveCompare(finalName) == .orderedSame
        }) {
            presets[index].settings = settings
        } else {
            presets.append(SavedEQPreset(name: finalName, settings: settings))
            if presets.count > Self.limit {
                presets.removeFirst(presets.count - Self.limit)
            }
        }
        persist()
    }

    public func delete(_ id: UUID) {
        presets.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        section.save(presets)
    }
}
