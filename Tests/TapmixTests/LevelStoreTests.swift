import XCTest
@testable import TapmixCore

final class LevelStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "tapmix-level-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testAudioUnitRoundTrips() throws {
        let store = LevelStore(defaults: defaults)
        var level = AppLevel()
        level.audioUnit = AudioUnitSelection(componentSubType: 17, componentManufacturer: 42)
        store.set(level, for: "com.example.a")

        let reloaded = LevelStore(defaults: defaults)
        XCTAssertEqual(reloaded.level(for: "com.example.a").audioUnit, level.audioUnit)
    }

    func testLevelsWithoutAudioUnitStillDecode() throws {
        let json = #"{"com.example.a":{"volume":0.5,"muted":false,"boost":1}}"#
        defaults.set(Data(json.utf8), forKey: "com.mardinli.tapmix.levels")

        let store = LevelStore(defaults: defaults)
        let level = store.level(for: "com.example.a")
        XCTAssertEqual(level.volume, 0.5)
        XCTAssertNil(level.audioUnit)
    }
}
