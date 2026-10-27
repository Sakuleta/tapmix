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

        store.set(AppLevel(volume: 1.4, muted: true, boost: 3), for: "com.example.app")

        let reloaded = LevelStore(defaults: defaults)
        XCTAssertEqual(reloaded.level(for: "com.example.app").volume, 1.4, accuracy: 0.0001)
        XCTAssertTrue(reloaded.level(for: "com.example.app").muted)
        XCTAssertEqual(reloaded.level(for: "com.example.app").boost, 3, accuracy: 0.0001)
        XCTAssertEqual(reloaded.level(for: "com.example.app").gain, 0)
    }

    func testBoostMultipliesGain() {
        XCTAssertEqual(AppLevel(volume: 1, boost: 2).gain, 2, accuracy: 0.0001)
        XCTAssertEqual(AppLevel(volume: 0.5, boost: 4).gain, 2, accuracy: 0.0001)
        XCTAssertEqual(AppLevel(volume: 2, boost: 4).gain, 8, accuracy: 0.0001)
    }

    func testLegacyLevelWithoutBoostDecodes() throws {
        let legacy = Data(#"{"volume":0.6,"muted":false}"#.utf8)
        let level = try JSONDecoder().decode(AppLevel.self, from: legacy)
        XCTAssertEqual(level.volume, 0.6, accuracy: 0.0001)
        XCTAssertEqual(level.boost, 1, accuracy: 0.0001)
        XCTAssertEqual(level.gain, 0.6, accuracy: 0.0001)
    }
}
