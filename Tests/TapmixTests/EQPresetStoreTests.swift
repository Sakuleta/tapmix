import XCTest
@testable import TapmixCore

final class EQPresetStoreTests: XCTestCase {
    func testSaveOverwriteReloadAndDelete() {
        let suiteName = "com.mardinli.tapmix.eqpresets.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = EQPresetStore(defaults: defaults)
        let filtered = EQSettings(
            enabled: true,
            gains: [3, 2, 1, 0, 0, 0, 0, 0, 0, 0],
            filters: [EQFilter(kind: .peaking, frequency: 1_000, gainDB: 6, q: 1)]
        )
        store.save(name: "Headphones", settings: filtered)
        XCTAssertEqual(store.presets.count, 1)
        XCTAssertEqual(store.presets[0].settings.filters.count, 1)

        store.save(name: "headphones", settings: EQSettings(enabled: true))
        XCTAssertEqual(store.presets.count, 1)
        XCTAssertTrue(store.presets[0].settings.filters.isEmpty)

        store.save(name: "Podcast", settings: EQPreset.vocal.settings)
        XCTAssertEqual(store.presets.count, 2)

        let reloaded = EQPresetStore(defaults: defaults)
        XCTAssertEqual(reloaded.presets.count, 2)
        XCTAssertEqual(reloaded.presets[1].name, "Podcast")

        reloaded.delete(reloaded.presets[0].id)
        XCTAssertEqual(reloaded.presets.count, 1)
        XCTAssertEqual(EQPresetStore(defaults: defaults).presets.count, 1)
    }

    func testEmptyNameGetsFallback() {
        let suiteName = "com.mardinli.tapmix.eqpresets.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = EQPresetStore(defaults: defaults)
        store.save(name: "  ", settings: EQSettings())
        XCTAssertEqual(store.presets.first?.name, "Preset 1")
    }
}
