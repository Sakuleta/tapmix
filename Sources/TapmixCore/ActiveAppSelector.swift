import Foundation

/// Picks the app a global hotkey should control: the audible one first, then
/// the frontmost app, then the one touched last.
public enum ActiveAppSelector {
    public static func bundleID(
        apps: [AppRow],
        frontmost: String?,
        lastActive: String?
    ) -> String? {
        guard !apps.isEmpty else { return nil }

        let playing = apps.filter(\.isPlaying)
        if !playing.isEmpty {
            if let lastActive, playing.contains(where: { $0.bundleID == lastActive }) {
                return lastActive
            }
            return playing.max { $0.level < $1.level }?.bundleID ?? playing[0].bundleID
        }

        if let frontmost, apps.contains(where: { $0.bundleID == frontmost }) {
            return frontmost
        }
        if let lastActive, apps.contains(where: { $0.bundleID == lastActive }) {
            return lastActive
        }
        return apps[0].bundleID
    }
}
