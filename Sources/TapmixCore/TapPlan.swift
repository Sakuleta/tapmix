import CoreAudio
import Foundation

/// The rule for which processes deserve a tap, and where each one plays.
///
/// Pure on purpose: the engine hands in the catalog, the live taps and whether
/// the process list could be read at all. A plan that is not `isComplete` means
/// "the hardware did not answer" — the caller keeps whatever is running instead
/// of tearing the mix down.
struct TapPlan: Equatable {
    let taps: [TapManager.DesiredTap]
    let isComplete: Bool

    static func make(
        groups: [AppGroup],
        availableUIDs: Set<String>,
        outputUID: String?,
        activeProcessIDs: Set<AudioObjectID>,
        processListReadable: Bool
    ) -> TapPlan {
        guard processListReadable else {
            return TapPlan(taps: [], isComplete: false)
        }

        var taps: [TapManager.DesiredTap] = []
        for group in groups {
            // A route that disappeared falls back to the system default rather
            // than muting the app.
            let route = group.level.outputUID.flatMap { availableUIDs.contains($0) ? $0 : nil }
            guard let target = route ?? outputUID else { continue }

            for processID in group.processObjectIDs
            where group.playingProcessObjectIDs.contains(processID)
                || activeProcessIDs.contains(processID)
            {
                taps.append(
                    TapManager.DesiredTap(
                        processObjectID: processID,
                        bundleID: group.bundleID,
                        displayName: group.name,
                        outputUID: target
                    )
                )
            }
        }
        return TapPlan(taps: taps, isComplete: true)
    }
}
