import XCTest
@testable import TapmixCore

final class SceneStoreTests: XCTestCase {
    func testSaveOverwriteDeleteAndReload() {
        let suiteName = "com.mardinli.tapmix.scenes.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SceneStore(defaults: defaults)
        store.save(name: "Meeting", levels: ["us.zoom.xos": AppLevel(volume: 0.4)])
        XCTAssertEqual(store.scenes.count, 1)

        store.save(name: "meeting", levels: ["us.zoom.xos": AppLevel(volume: 0.6)])
        XCTAssertEqual(store.scenes.count, 1)
        XCTAssertEqual(store.scenes[0].levels["us.zoom.xos"]?.volume, 0.6)

        store.save(name: "Music", levels: ["com.spotify.client": AppLevel(volume: 1.2, boost: 2)])
        XCTAssertEqual(store.scenes.count, 2)

        let reloaded = SceneStore(defaults: defaults)
        XCTAssertEqual(reloaded.scenes.count, 2)
        XCTAssertEqual(reloaded.scenes[1].levels["com.spotify.client"]?.boost, 2)

        reloaded.delete(reloaded.scenes[0].id)
        XCTAssertEqual(reloaded.scenes.count, 1)
        XCTAssertEqual(SceneStore(defaults: defaults).scenes.count, 1)
    }

    func testEmptyNameGetsFallback() {
        let suiteName = "com.mardinli.tapmix.scenes.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SceneStore(defaults: defaults)
        store.save(name: "   ", levels: [:])
        XCTAssertEqual(store.scenes.first?.name, "Scene 1")
    }
}
