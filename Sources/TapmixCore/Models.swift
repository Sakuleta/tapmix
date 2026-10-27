import AppKit
import Foundation

public struct AppLevel: Codable, Equatable {
    public var volume: Float
    public var muted: Bool

    public init(volume: Float = 1, muted: Bool = false) {
        self.volume = volume
        self.muted = muted
    }

    public var gain: Float {
        muted ? 0 : min(max(volume, 0), 2)
    }
}

/// Persists per-bundle volume/mute state as JSON in UserDefaults.
public final class LevelStore {
    private static let key = "com.sakuleta.tapmix.levels"

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

    public init(
        bundleID: String,
        name: String,
        icon: NSImage?,
        isPlaying: Bool,
        volume: Float,
        muted: Bool
    ) {
        self.bundleID = bundleID
        self.name = name
        self.icon = icon
        self.isPlaying = isPlaying
        self.volume = volume
        self.muted = muted
    }
}
