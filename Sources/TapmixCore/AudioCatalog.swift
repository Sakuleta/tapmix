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
    let capturingProcessObjectIDs: [AudioObjectID]
    let level: AppLevel
    let pinned: Bool

    var row: AppRow {
        AppRow(
            bundleID: bundleID,
            name: name,
            icon: icon,
            isPlaying: isPlaying,
            isInCall: !capturingProcessObjectIDs.isEmpty,
            volume: level.volume,
            muted: level.muted,
            boost: level.boost,
            pinned: pinned,
            eq: level.eq,
            routeUID: level.outputUID,
            nightMode: level.nightMode,
            balance: level.balance,
            mono: level.mono,
            audioUnit: level.audioUnit
        )
    }
}

/// Pure grouping policy: which processes become rows, under which host, in what order.
enum AudioCatalog {
    static func groups(
        processes: [AudioProcess],
        running: [RunningAppDescriptor],
        levels: [String: AppLevel],
        activeBundleIDs: Set<String>,
        pinnedBundleIDs: Set<String> = [],
        ignoredBundleIDs: Set<String> = []
    ) -> [AppGroup] {
        var grouped: [String: [AudioProcess]] = [:]
        var identities: [String: AppIdentity] = [:]

        for process in processes where !process.bundleID.isEmpty {
            guard let identity = AppResolver.resolve(process, running: running) else { continue }
            grouped[identity.bundleID, default: []].append(process)
            identities[identity.bundleID] = identity
        }

        return grouped.compactMap { bundleID, bundleProcesses in
            guard let identity = identities[bundleID], !ignoredBundleIDs.contains(bundleID) else {
                return nil
            }
            let playing = bundleProcesses.contains { $0.isPlaying }
            let pinned = pinnedBundleIDs.contains(bundleID)
            guard playing || pinned || levels[bundleID] != nil || activeBundleIDs.contains(bundleID) else {
                return nil
            }
            return AppGroup(
                bundleID: bundleID,
                name: identity.name,
                icon: identity.icon,
                isPlaying: playing,
                processObjectIDs: bundleProcesses.map(\.objectID),
                playingProcessObjectIDs: bundleProcesses.filter(\.isPlaying).map(\.objectID),
                capturingProcessObjectIDs: bundleProcesses.filter(\.isCapturing).map(\.objectID),
                level: levels[bundleID] ?? AppLevel(),
                pinned: pinned
            )
        }.sorted {
            if $0.pinned != $1.pinned {
                return $0.pinned
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
