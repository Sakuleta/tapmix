import Foundation

/// Decides when other apps should duck. The engine reports which processes
/// capture input; no microphone audio is read. Only call apps and browsers
/// trigger ducking, so recorders and utilities that keep the mic open do not.
public struct DuckingPolicy {
    public static let duckDelay: TimeInterval = 1.0
    public static let releaseDelay: TimeInterval = 1.5
    public static let duckFactor: Float = 0.3

    public static let knownCallBundleIDs: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.apple.FaceTime",
        "com.hnc.Discord",
        "com.tinyspeck.slackmacgap",
        "net.whatsapp.WhatsApp",
        "com.skype.skype",
        "com.cisco.webexmeetingsapp"
    ]

    /// Browsers can host web meetings; their microphone use counts as a call.
    public static let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "company.thebrowser.Browser"
    ]

    private var micStartedAt: Date?
    private var micStoppedAt: Date?
    private var callBundleID: String?
    public private(set) var isDucking = false

    public init() {}

    /// Returns the new ducking state.
    public mutating func update(inputBundleIDs: Set<String>, now: Date) -> Bool {
        if let owner = Self.callOwner(in: inputBundleIDs) {
            micStoppedAt = nil
            if micStartedAt == nil {
                micStartedAt = now
                callBundleID = owner
            }
            if !isDucking, let startedAt = micStartedAt,
               now.timeIntervalSince(startedAt) >= Self.duckDelay {
                isDucking = true
            }
        } else {
            micStartedAt = nil
            if isDucking {
                if micStoppedAt == nil {
                    micStoppedAt = now
                }
                if let stoppedAt = micStoppedAt,
                   now.timeIntervalSince(stoppedAt) >= Self.releaseDelay {
                    isDucking = false
                    micStoppedAt = nil
                    callBundleID = nil
                }
            } else {
                micStoppedAt = nil
                callBundleID = nil
            }
        }
        return isDucking
    }

    /// The active call app is never ducked, nor is a known conferencing app.
    public func isExempt(bundleID: String) -> Bool {
        Self.knownCallBundleIDs.contains(bundleID) || callBundleID == bundleID
    }

    private static func callOwner(in bundleIDs: Set<String>) -> String? {
        bundleIDs.intersection(knownCallBundleIDs).min()
            ?? bundleIDs.intersection(browserBundleIDs).min()
    }

    public mutating func reset() {
        micStartedAt = nil
        micStoppedAt = nil
        callBundleID = nil
        isDucking = false
    }
}
