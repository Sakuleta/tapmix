import CoreAudio
import Foundation

/// Owns every process tap: creation, gain, stall detection and retry backoff.
/// The engine polls and builds rows; it does not keep lifecycle state.
@MainActor
final class TapManager {
    struct DesiredTap: Equatable {
        let processObjectID: AudioObjectID
        let bundleID: String
        let displayName: String
    }

    enum Health: Equatable {
        case ok
        case stalled(displayName: String, message: String)
    }

    typealias TapFactory = (AudioObjectID, String, String) -> any TapControlling

    static let healthWindow: TimeInterval = 6
    static let retryDelays: [TimeInterval] = [15, 30, 60, 120, 300]

    private struct Failure {
        var attempts: Int
        var retryAt: Date
        var bundleID: String
        var displayName: String
        var detail: String
    }

    private let makeTap: TapFactory
    private let now: () -> Date
    private var taps: [AudioObjectID: any TapControlling] = [:]
    private var failures: [AudioObjectID: Failure] = [:]
    private var gains: [String: Float] = [:]
    private var outputUID: String?
    private(set) var health: Health = .ok

    init(
        makeTap: @escaping TapFactory = { processID, bundleID, outputUID in
            TapController(
                processObjectID: processID,
                bundleID: bundleID,
                outputDeviceUID: outputUID
            )
        },
        now: @escaping () -> Date = Date.init
    ) {
        self.makeTap = makeTap
        self.now = now
    }

    var activeProcessIDs: Set<AudioObjectID> { Set(taps.keys) }
    var activeBundleIDs: Set<String> { Set(taps.values.map(\.bundleID)) }

    func setGain(_ gain: Float, for bundleID: String) {
        let clamped = AudioMath.clampedGain(gain)
        gains[bundleID] = clamped
        for tap in taps.values where tap.bundleID == bundleID {
            tap.setGain(clamped)
        }
    }

    func sync(desired: [DesiredTap], outputUID: String) {
        let unique = Dictionary(desired.map { ($0.processObjectID, $0) }, uniquingKeysWith: { first, _ in first })
        let desiredIDs = Set(unique.keys)

        if self.outputUID != outputUID {
            stopAllTaps()
            failures.removeAll()
            self.outputUID = outputUID
        }

        let stale = Array(taps.keys).filter { !desiredIDs.contains($0) }
        for id in stale {
            taps[id]?.stop()
            taps[id] = nil
            failures[id] = nil
        }

        for id in desiredIDs.sorted() {
            guard let desiredTap = unique[id] else { continue }
            if let tap = taps[id] {
                tap.setGain(gains[tap.bundleID] ?? 1)
                continue
            }
            if let failure = failures[id], now() < failure.retryAt {
                continue
            }

            let tap = makeTap(id, desiredTap.bundleID, outputUID)
            do {
                try tap.start()
                tap.setGain(gains[desiredTap.bundleID] ?? 1)
                taps[id] = tap
                failures[id] = nil
            } catch {
                recordFailure(for: desiredTap, detail: error.localizedDescription)
            }
        }

        checkHealth(desired: unique)
        recomputeHealth()
    }

    func retry() {
        failures.removeAll()
        health = .ok
    }

    func stopAll() {
        stopAllTaps()
        failures.removeAll()
        health = .ok
    }

    private func stopAllTaps() {
        for tap in taps.values {
            tap.stop()
        }
        taps.removeAll()
    }

    /// A stalled tap stops only itself; every healthy tap keeps running.
    private func checkHealth(desired: [AudioObjectID: DesiredTap]) {
        var stalled: [AudioObjectID] = []
        for (id, tap) in taps where desired[id] != nil {
            if tap.callbackCount == 0, now().timeIntervalSince(tap.createdAt) > Self.healthWindow {
                stalled.append(id)
            }
        }
        for id in stalled {
            guard let tap = taps[id], let desiredTap = desired[id] else { continue }
            tap.stop()
            taps[id] = nil
            recordFailure(for: desiredTap, detail: "No audio is arriving.")
        }
    }

    private func recordFailure(for desiredTap: DesiredTap, detail: String) {
        let previousAttempts = failures[desiredTap.processObjectID]?.attempts ?? 0
        let attempts = previousAttempts + 1
        let index = min(attempts - 1, Self.retryDelays.count - 1)
        failures[desiredTap.processObjectID] = Failure(
            attempts: attempts,
            retryAt: now().addingTimeInterval(Self.retryDelays[index]),
            bundleID: desiredTap.bundleID,
            displayName: desiredTap.displayName,
            detail: detail
        )
    }

    private func recomputeHealth() {
        guard let failure = failures.values.min(by: { $0.retryAt < $1.retryAt }) else {
            health = .ok
            return
        }
        health = .stalled(
            displayName: failure.displayName,
            message: "\(failure.detail) Allow “Tapmix” in System Settings → Privacy & Security → Screen & System Audio Recording. Retrying automatically; press Retry to try now."
        )
    }
}
