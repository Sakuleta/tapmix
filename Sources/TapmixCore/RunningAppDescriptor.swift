import AppKit
import Foundation

/// Value snapshot of one running application, so host resolution stays testable.
struct RunningAppDescriptor {
    let pid: pid_t
    let bundleID: String?
    let name: String
    let icon: NSImage?
    let isRegular: Bool
    let isProhibited: Bool
    let bundlePath: String?
    let executablePath: String?

    static func snapshot(_ apps: [NSRunningApplication]) -> [RunningAppDescriptor] {
        apps.map { app in
            RunningAppDescriptor(
                pid: app.processIdentifier,
                bundleID: app.bundleIdentifier,
                name: app.localizedName ?? app.bundleIdentifier ?? "Unknown",
                icon: app.icon,
                isRegular: app.activationPolicy == .regular,
                isProhibited: app.activationPolicy == .prohibited,
                bundlePath: app.bundleURL?.resolvingSymlinksInPath().path,
                executablePath: app.executableURL?.resolvingSymlinksInPath().path
            )
        }
    }
}
