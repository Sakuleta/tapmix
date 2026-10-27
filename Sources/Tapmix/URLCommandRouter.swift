import Foundation
import TapmixCore

@MainActor
enum URLCommandRouter {
    static func handle(_ url: URL) {
        guard let command = TapmixURLCommand.parse(url) else { return }
        let engine = AudioEngine.shared

        switch command {
        case let .setVolume(bundleID, volume):
            engine.setVolume(bundleID, Double(volume))
        case let .stepVolume(bundleID, delta):
            engine.stepVolume(bundleID, by: delta)
        case let .setMute(bundleID, muted):
            engine.setMuted(bundleID, muted)
        case let .toggleMute(bundleID):
            engine.toggleMute(bundleID)
        case let .setBoost(bundleID, boost):
            engine.setBoost(bundleID, boost)
        case let .setRoute(bundleID, deviceUID):
            engine.setRoute(bundleID, deviceUID)
        }
    }
}
