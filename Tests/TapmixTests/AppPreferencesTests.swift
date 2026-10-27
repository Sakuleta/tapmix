import XCTest
@testable import TapmixCore

final class AppPreferencesTests: XCTestCase {
    func testPinAndIgnoreRoundTrip() {
        let suiteName = "com.mardinli.tapmix.preferences.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppPreferences(defaults: defaults)
        preferences.set(AppPreference(pinned: true, name: "Brave Browser"), for: "com.brave.Browser")
        preferences.set(AppPreference(ignored: true, name: "Zoom"), for: "us.zoom.xos")

        let reloaded = AppPreferences(defaults: defaults)
        XCTAssertTrue(reloaded.preference(for: "com.brave.Browser").pinned)
        XCTAssertEqual(reloaded.preference(for: "com.brave.Browser").name, "Brave Browser")
        XCTAssertTrue(reloaded.preference(for: "us.zoom.xos").ignored)
        XCTAssertEqual(reloaded.pinnedBundleIDs, ["com.brave.Browser"])
        XCTAssertEqual(reloaded.ignoredBundleIDs, ["us.zoom.xos"])
        XCTAssertFalse(reloaded.preference(for: "com.example.missing").pinned)
        XCTAssertFalse(reloaded.preference(for: "com.example.missing").ignored)
    }
}
