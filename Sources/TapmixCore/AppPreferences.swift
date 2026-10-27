import Foundation

public struct AppPreference: Codable, Equatable {
    public var pinned: Bool
    public var ignored: Bool
    public var name: String?

    public init(pinned: Bool = false, ignored: Bool = false, name: String? = nil) {
        self.pinned = pinned
        self.ignored = ignored
        self.name = name
    }
}

/// Persists pin/hide choices separately from audio levels, so unpinning an app
/// can still let its stored volume keep the row visible.
public final class AppPreferences {
    private static let key = "com.mardinli.tapmix.preferences"

    private let defaults: UserDefaults
    private var preferences: [String: AppPreference]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: AppPreference].self, from: data) {
            preferences = decoded
        } else {
            preferences = [:]
        }
    }

    public func preference(for bundleID: String) -> AppPreference {
        preferences[bundleID] ?? AppPreference()
    }

    public func set(_ preference: AppPreference, for bundleID: String) {
        preferences[bundleID] = preference
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: Self.key)
        }
    }

    public var all: [String: AppPreference] {
        preferences
    }

    public var pinnedBundleIDs: Set<String> {
        Set(preferences.filter { $0.value.pinned }.keys)
    }

    public var ignoredBundleIDs: Set<String> {
        Set(preferences.filter { $0.value.ignored }.keys)
    }
}
