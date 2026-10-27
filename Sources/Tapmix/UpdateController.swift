import AppKit
import Sparkle

/// Sparkle's standard updater. The feed URL and EdDSA public key live in
/// Info.plist; automatic checks run once a day and the menu can ask on demand.
@MainActor
final class UpdateController: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    static let shared = UpdateController()

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: self
    )

    private override init() {
        super.init()
    }

    func start() {
        controller.startUpdater()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// A menu bar app has no window to bring forward, so scheduled checks use
    /// Sparkle's gentle reminders instead of an alert behind other apps.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        true
    }
}
