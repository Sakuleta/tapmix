import AppKit
import Foundation

public struct AppLevel: Codable, Equatable {
    public var volume: Float
    public var muted: Bool
    /// Extra gain on top of `volume`: 1x, 2x, 3x or 4x.
    public var boost: Float

    public init(volume: Float = 1, muted: Bool = false, boost: Float = 1) {
        self.volume = volume
        self.muted = muted
        self.boost = boost
    }

    public var gain: Float {
        muted ? 0 : min(max(volume, 0), 2) * min(max(boost, 1), 4)
    }

    private enum CodingKeys: String, CodingKey {
        case volume, muted, boost
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        volume = try container.decodeIfPresent(Float.self, forKey: .volume) ?? 1
        muted = try container.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        boost = try container.decodeIfPresent(Float.self, forKey: .boost) ?? 1
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(volume, forKey: .volume)
        try container.encode(muted, forKey: .muted)
        try container.encode(boost, forKey: .boost)
    }
}

/// Persists per-bundle volume/mute state as JSON in UserDefaults.
public final class LevelStore {
    private static let key = "com.mardinli.tapmix.levels"

    private let defaults: UserDefaults
    private var levels: [String: AppLevel]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: AppLevel].self, from: data) {
            levels = decoded
        } else {
            levels = [:]
        }
    }

    public func level(for bundleID: String) -> AppLevel {
        levels[bundleID] ?? AppLevel()
    }

    public func set(_ level: AppLevel, for bundleID: String) {
        levels[bundleID] = level
        if let data = try? JSONEncoder().encode(levels) {
            defaults.set(data, forKey: Self.key)
        }
    }

    public func hasLevel(for bundleID: String) -> Bool {
        levels[bundleID] != nil
    }

    public var allLevels: [String: AppLevel] { levels }
}

/// One row in the menu bar panel. Processes that share a host application are grouped.
public struct AppRow: Identifiable, Equatable {
    public var id: String { bundleID }

    public let bundleID: String
    public let name: String
    public let icon: NSImage?
    public let isPlaying: Bool
    public var volume: Float
    public var muted: Bool
    public var boost: Float
    public let pinned: Bool
    /// Latest output peak in 0...1, updated by the meter timer.
    public var level: Float

    public init(
        bundleID: String,
        name: String,
        icon: NSImage?,
        isPlaying: Bool,
        volume: Float,
        muted: Bool,
        boost: Float = 1,
        pinned: Bool = false,
        level: Float = 0
    ) {
        self.bundleID = bundleID
        self.name = name
        self.icon = icon
        self.isPlaying = isPlaying
        self.volume = volume
        self.muted = muted
        self.boost = boost
        self.pinned = pinned
        self.level = level
    }
}

/// An app the person asked Tapmix to leave alone; listed only so it can be restored.
public struct HiddenApp: Identifiable, Equatable {
    public var id: String { bundleID }
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}
