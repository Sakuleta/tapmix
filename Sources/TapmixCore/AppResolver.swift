import AppKit
import Foundation

struct AppIdentity {
    let bundleID: String
    let name: String
    let icon: NSImage?
}

/// Maps Core Audio process objects (including XPC/helper processes) back to the
/// application a person recognises in the menu bar.
enum AppResolver {
    private static let ignoredPrefixes = [
        "com.apple.siri",
        "com.apple.Siri",
        "com.apple.assistant",
        "com.apple.audio",
        "com.apple.coreaudio",
        "com.apple.mediaremote",
        "com.apple.accessibility.heard",
        "com.apple.hearingd",
        "com.apple.voicebankingd",
        "com.apple.systemsound",
        "com.apple.FrontBoardServices",
        "com.apple.frontboard",
        "com.apple.springboard",
        "com.apple.notificationcenter",
        "com.apple.NotificationCenter",
        "com.apple.UserNotifications",
        "com.apple.usernotifications",
        "com.apple.SpeechRecognitionCore",
        "com.apple.speech",
        "com.apple.dictation",
        "com.apple.corespeech",
        "com.apple.CoreSpeech",
        "com.apple.VoiceControl",
        "com.apple.voicecontrol",
        "com.apple.controlcenter",
        "com.apple.ControlCenter",
        "com.apple.avconferenced",
        "com.apple.cmio",
        "com.rogueamoeba",
        "com.bearisdriving.BGM"
    ]

    private static let ignoredNames = [
        "systemsoundserverd",
        "systemsoundserv",
        "coreaudiod",
        "audiomxd",
        "speechrecognitiond",
        "dictationd",
        "corespeech"
    ]

    static func resolve(_ process: AudioProcess, running: [RunningAppDescriptor]) -> AppIdentity? {
        let ownBundleID = Bundle.main.bundleIdentifier
        if process.bundleID == ownBundleID || process.bundleID == "com.mardinli.tapmix" {
            return nil
        }

        let direct = running.first { $0.pid == process.pid }
        var host: RunningAppDescriptor?

        if let direct, direct.isRegular, direct.bundlePath?.hasSuffix(".app") == true {
            host = direct
        }

        if host == nil, let executable = direct?.executablePath {
            host = running.first { app in
                guard !app.isProhibited, let path = app.bundlePath else { return false }
                return executable == path || executable.hasPrefix(path + "/")
            }
        }

        // Hide daemons and orphan helpers: only real, user-facing applications get a row.
        guard let host, let bundleID = host.bundleID else { return nil }

        let name = host.name.isEmpty
            ? (bundleID.split(separator: ".").last.map(String.init) ?? bundleID)
            : host.name

        guard !bundleID.isEmpty, !isIgnored(bundleID: bundleID, name: name) else {
            return nil
        }

        let icon = host.icon
            ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)

        return AppIdentity(bundleID: bundleID, name: name, icon: icon)
    }

    private static func isIgnored(bundleID: String, name: String) -> Bool {
        if ignoredPrefixes.contains(where: { bundleID.hasPrefix($0) }) {
            return true
        }
        let lowered = name.lowercased()
        return ignoredNames.contains(where: { lowered.hasPrefix($0) })
    }
}
