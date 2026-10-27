import Foundation

/// Decides when other apps should duck. The engine only tells it whether any
/// input device is running; no microphone audio is read.
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

    private var micStartedAt: Date?
    private var micStoppedAt: Date?
    private var callBundleID: String?
    public private(set) var isDucking = false

    public init() {}

    /// Returns the new ducking state.
    public mutating func update(micActive: Bool, frontmost: String?, now: Date) -> Bool {
        if micActive {
            micStoppedAt = nil
            if micStartedAt == nil {
                micStartedAt = now
                callBundleID = frontmost
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

    /// The call app is never ducked, nor is a known conferencing app.
    public func isExempt(bundleID: String) -> Bool {
        Self.knownCallBundleIDs.contains(bundleID) || callBundleID == bundleID
    }

    public mutating func reset() {
        micStartedAt = nil
        micStoppedAt = nil
        callBundleID = nil
        isDucking = false
    }
}
