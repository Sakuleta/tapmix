import AppKit
import CoreAudio
import Foundation

struct AppGroup {
    let bundleID: String
    let name: String
    let icon: NSImage?
    let isPlaying: Bool
    let processObjectIDs: [AudioObjectID]
    let playingProcessObjectIDs: [AudioObjectID]
    let level: AppLevel

    var row: AppRow {
        AppRow(
            bundleID: bundleID,
            name: name,
            icon: icon,
            isPlaying: isPlaying,
            volume: level.volume,
            muted: level.muted,
            boost: level.boost
        )
    }
}

/// Pure grouping policy: which processes become rows, under which host, in what order.
enum AudioCatalog {
    static func groups(
        processes: [AudioProcess],
        running: [RunningAppDescriptor],
        levels: [String: AppLevel],
        activeBundleIDs: Set<String>
    ) -> [AppGroup] {
        var grouped: [String: [AudioProcess]] = [:]
        var identities: [String: AppIdentity] = [:]

        for process in processes where !process.bundleID.isEmpty {
            guard let identity = AppResolver.resolve(process, running: running) else { continue }
            grouped[identity.bundleID, default: []].append(process)
            identities[identity.bundleID] = identity
        }

        return grouped.compactMap { bundleID, bundleProcesses in
            guard let identity = identities[bundleID] else { return nil }
            let playing = bundleProcesses.contains { $0.isPlaying }
            guard playing || levels[bundleID] != nil || activeBundleIDs.contains(bundleID) else {
                return nil
            }
            return AppGroup(
                bundleID: bundleID,
                name: identity.name,
                icon: identity.icon,
                isPlaying: playing,
                processObjectIDs: bundleProcesses.map(\.objectID),
                playingProcessObjectIDs: bundleProcesses.filter(\.isPlaying).map(\.objectID),
                level: levels[bundleID] ?? AppLevel()
            )
        }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
