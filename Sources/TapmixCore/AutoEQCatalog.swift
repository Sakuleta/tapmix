import Foundation

public struct AutoEQProfile: Identifiable, Equatable, Sendable {
    public let name: String
    public let url: URL

    public var id: String { url.path }

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
    }
}

/// Indexes a local AutoEQ results folder. Nothing is downloaded or bundled.
public enum AutoEQCatalog {
    public static func scan(folder: URL) -> [AutoEQProfile] {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var profiles: [AutoEQProfile] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent.caseInsensitiveCompare("ParametricEQ.txt") == .orderedSame
            else { continue }

            let parent = url.deletingLastPathComponent().lastPathComponent
            profiles.append(
                AutoEQProfile(
                    name: parent.isEmpty ? url.lastPathComponent : parent,
                    url: url
                )
            )
            if profiles.count >= 5_000 { break }
        }

        return profiles.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    public static func filters(for profile: AutoEQProfile) -> [EQFilter] {
        guard let text = try? String(contentsOf: profile.url, encoding: .utf8) else {
            return []
        }
        return EQFilterParser.parse(text)
    }
}
