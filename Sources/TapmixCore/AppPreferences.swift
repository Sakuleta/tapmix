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

    private let section: DefaultsSection<[String: AppPreference]>
    private var preferences: [String: AppPreference]

    public init(defaults: UserDefaults = .standard) {
        section = DefaultsSection(defaults: defaults, key: Self.key)
        preferences = section.load(default: [:])
    }

    public func preference(for bundleID: String) -> AppPreference {
        preferences[bundleID] ?? AppPreference()
    }

    public func set(_ preference: AppPreference, for bundleID: String) {
        preferences[bundleID] = preference
        section.save(preferences)
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
