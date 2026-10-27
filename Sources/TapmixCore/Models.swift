import AppKit
import Foundation

public struct AppLevel: Codable, Equatable {
    public var volume: Float
    public var muted: Bool
    /// Extra gain on top of `volume`: 1x, 2x, 3x or 4x.
    public var boost: Float
    public var eq: EQSettings
    /// Explicit output device; `nil` follows the system default.
    public var outputUID: String?
    public var nightMode: Bool
    /// -1 is full left, 0 is center, +1 is full right.
    public var balance: Float
    public var mono: Bool

    public init(
        volume: Float = 1,
        muted: Bool = false,
        boost: Float = 1,
        eq: EQSettings = EQSettings(),
        outputUID: String? = nil,
        nightMode: Bool = false,
        balance: Float = 0,
        mono: Bool = false
    ) {
        self.volume = volume
        self.muted = muted
        self.boost = boost
        self.eq = eq
        self.outputUID = outputUID
        self.nightMode = nightMode
        self.balance = balance
        self.mono = mono
    }

    public var gain: Float {
        muted ? 0 : min(max(volume, 0), 2) * min(max(boost, 1), 4)
    }

    private enum CodingKeys: String, CodingKey {
        case volume, muted, boost, eq, outputUID, nightMode, balance, mono
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        volume = try container.decodeIfPresent(Float.self, forKey: .volume) ?? 1
        muted = try container.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        boost = try container.decodeIfPresent(Float.self, forKey: .boost) ?? 1
        eq = try container.decodeIfPresent(EQSettings.self, forKey: .eq) ?? EQSettings()
        outputUID = try container.decodeIfPresent(String.self, forKey: .outputUID)
        nightMode = try container.decodeIfPresent(Bool.self, forKey: .nightMode) ?? false
        balance = try container.decodeIfPresent(Float.self, forKey: .balance) ?? 0
        mono = try container.decodeIfPresent(Bool.self, forKey: .mono) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(volume, forKey: .volume)
        try container.encode(muted, forKey: .muted)
        try container.encode(boost, forKey: .boost)
        try container.encode(eq, forKey: .eq)
        try container.encodeIfPresent(outputUID, forKey: .outputUID)
        try container.encode(nightMode, forKey: .nightMode)
        try container.encode(balance, forKey: .balance)
        try container.encode(mono, forKey: .mono)
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
    public var eq: EQSettings
    public var routeUID: String?
    public var nightMode: Bool
    public var balance: Float
    public var mono: Bool

    public init(
        bundleID: String,
        name: String,
        icon: NSImage?,
        isPlaying: Bool,
        volume: Float,
        muted: Bool,
        boost: Float = 1,
        pinned: Bool = false,
        level: Float = 0,
        eq: EQSettings = EQSettings(),
        routeUID: String? = nil,
        nightMode: Bool = false,
        balance: Float = 0,
        mono: Bool = false
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
        self.eq = eq
        self.routeUID = routeUID
        self.nightMode = nightMode
        self.balance = balance
        self.mono = mono
    }
}

public struct ActiveVolumeState: Equatable {
    public let bundleID: String
    public let name: String
    public let volume: Float
    public let muted: Bool

    public init(bundleID: String, name: String, volume: Float, muted: Bool) {
        self.bundleID = bundleID
        self.name = name
        self.volume = volume
        self.muted = muted
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
