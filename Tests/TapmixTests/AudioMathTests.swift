import XCTest
@testable import TapmixCore

final class AudioMathTests: XCTestCase {
    func testLevelStoreRoundTrip() {
        let suiteName = "com.mardinli.tapmix.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LevelStore(defaults: defaults)
        XCTAssertEqual(store.level(for: "com.example.app").volume, 1)
        XCTAssertFalse(store.level(for: "com.example.app").muted)

        store.set(AppLevel(volume: 1.4, muted: true), for: "com.example.app")

        let reloaded = LevelStore(defaults: defaults)
        XCTAssertEqual(reloaded.level(for: "com.example.app").volume, 1.4, accuracy: 0.0001)
        XCTAssertTrue(reloaded.level(for: "com.example.app").muted)
        XCTAssertEqual(reloaded.level(for: "com.example.app").gain, 0)
    }
}
