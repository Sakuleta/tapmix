import Foundation

public enum TapmixURLCommand: Equatable {
    case setVolume(bundleID: String, volume: Float)
    case stepVolume(bundleID: String, delta: Float)
    case setMute(bundleID: String, muted: Bool)
    case toggleMute(bundleID: String)
    case setBoost(bundleID: String, boost: Float)
    case setRoute(bundleID: String, deviceUID: String?)

    public static func parse(_ url: URL) -> TapmixURLCommand? {
        guard url.scheme?.lowercased() == "tapmix",
              let action = url.host?.lowercased(),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        let app = value("app")?.trimmingCharacters(in: .whitespaces)

        switch action {
        case "set-volume":
            guard let app, !app.isEmpty, let percent = value("volume").flatMap(Float.init) else {
                return nil
            }
            return .setVolume(bundleID: app, volume: min(max(percent / 100, 0), 2))

        case "step-volume":
            guard let app, !app.isEmpty else { return nil }
            let percent = value("delta").flatMap(Float.init) ?? 5
            return .stepVolume(bundleID: app, delta: min(max(percent / 100, -0.5), 0.5))

        case "set-mute":
            guard let app, !app.isEmpty, let raw = value("muted") else { return nil }
            let muted = ["1", "true", "yes", "on"].contains(raw.lowercased())
            return .setMute(bundleID: app, muted: muted)

        case "toggle-mute":
            guard let app, !app.isEmpty else { return nil }
            return .toggleMute(bundleID: app)

        case "set-boost":
            guard let app, !app.isEmpty, let boost = value("boost").flatMap(Float.init) else {
                return nil
            }
            return .setBoost(bundleID: app, boost: min(max(boost, 1), 4))

        case "set-route":
            guard let app, !app.isEmpty else { return nil }
            let device = value("device").flatMap { $0.isEmpty ? nil : $0 }
            return .setRoute(bundleID: app, deviceUID: device)

        default:
            return nil
        }
    }
}
