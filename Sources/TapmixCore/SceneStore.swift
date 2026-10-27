import Foundation

public struct MixScene: Codable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var levels: [String: AppLevel]
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, levels: [String: AppLevel], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.levels = levels
        self.createdAt = createdAt
    }
}

/// Named snapshots of every stored per-app level. Scenes live in UserDefaults
/// alongside the level store, so applying one works even for apps that are not
/// running at the moment.
public final class SceneStore {
    private static let key = "com.mardinli.tapmix.scenes"
    private static let limit = 20

    private let defaults: UserDefaults
    public private(set) var scenes: [MixScene]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([MixScene].self, from: data) {
            scenes = decoded
        } else {
            scenes = []
        }
    }

    public func save(name: String, levels: [String: AppLevel]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Scene \(scenes.count + 1)" : trimmed

        if let index = scenes.firstIndex(where: {
            $0.name.caseInsensitiveCompare(finalName) == .orderedSame
        }) {
            scenes[index].levels = levels
            scenes[index].createdAt = Date()
        } else {
            scenes.append(MixScene(name: finalName, levels: levels))
            if scenes.count > Self.limit {
                scenes.removeFirst(scenes.count - Self.limit)
            }
        }
        persist()
    }

    public func delete(_ id: UUID) {
        scenes.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(scenes) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
