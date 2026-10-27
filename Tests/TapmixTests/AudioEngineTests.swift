import XCTest
@testable import TapmixCore

/// User actions, without touching the HAL: the engine is built on isolated
/// defaults and no method here calls `refresh()`.
@MainActor
final class AudioEngineTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: LevelStore!
    private var engine: AudioEngine!

    override func setUp() {
        super.setUp()
        suiteName = "tapmix-engine-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = LevelStore(defaults: defaults)
        engine = AudioEngine(
            store: store,
            preferences: AppPreferences(defaults: defaults),
            sceneStore: SceneStore(defaults: defaults),
            eqPresetStore: EQPresetStore(defaults: defaults)
        )
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        engine = nil
        store = nil
        defaults = nil
        super.tearDown()
    }

    func testVolumeClampsToTheSupportedRange() {
        engine.setVolume("com.a", 3)
        XCTAssertEqual(store.level(for: "com.a").volume, 2)

        engine.setVolume("com.a", -1)
        XCTAssertEqual(store.level(for: "com.a").volume, 0)
    }

    func testMuteFlowsIntoTheEffectiveGain() {
        engine.setMuted("com.a", true)

        XCTAssertTrue(store.level(for: "com.a").muted)
        XCTAssertEqual(store.level(for: "com.a").gain, 0)
    }

    func testStepVolumeClampsAndUnmutes() {
        engine.setMuted("com.a", true)
        engine.setVolume("com.a", 2)

        engine.stepVolume("com.a", by: 0.5)

        XCTAssertEqual(store.level(for: "com.a").volume, 2)
        XCTAssertFalse(store.level(for: "com.a").muted)
    }

    func testBoostClampsToOneThroughFour() {
        engine.setBoost("com.a", 9)
        XCTAssertEqual(store.level(for: "com.a").boost, 4)

        engine.setBoost("com.a", 0)
        XCTAssertEqual(store.level(for: "com.a").boost, 1)
    }

    func testBalanceClampsToFullLeftAndRight() {
        engine.setBalance("com.a", -4)
        XCTAssertEqual(store.level(for: "com.a").balance, -1)

        engine.setBalance("com.a", 4)
        XCTAssertEqual(store.level(for: "com.a").balance, 1)
    }

    func testProcessingTogglesPersist() {
        engine.setNightMode("com.a", true)
        engine.setMono("com.a", true)

        XCTAssertTrue(store.level(for: "com.a").nightMode)
        XCTAssertTrue(store.level(for: "com.a").mono)
    }

    func testEQPersists() {
        var settings = EQSettings()
        settings.enabled = true
        settings.gains[0] = 4

        engine.setEQ("com.a", settings)

        XCTAssertEqual(store.level(for: "com.a").eq, settings)
    }

    func testAudioUnitSelectionPersists() {
        let selection = AudioUnitSelection(componentSubType: 17, componentManufacturer: 42)

        engine.setAudioUnit("com.a", selection)

        XCTAssertEqual(store.level(for: "com.a").audioUnit, selection)
    }

    func testSavingAndDeletingAScene() {
        engine.setVolume("com.a", 0.4)
        engine.saveScene(named: "Quiet")

        XCTAssertEqual(engine.scenes.map(\.name), ["Quiet"])
        let scene = try? XCTUnwrap(engine.scenes.first)
        if let scene {
            XCTAssertEqual(scene.levels["com.a"]?.volume, 0.4)
        }

        if let scene {
            engine.deleteScene(scene.id)
        }
        XCTAssertTrue(engine.scenes.isEmpty)
    }

    func testEQPresetsSaveAndDelete() {
        var settings = EQSettings()
        settings.enabled = true
        engine.setEQ("com.a", settings)

        engine.saveEQPreset("Headphones", for: "com.a")
        XCTAssertEqual(engine.eqPresets.map(\.name), ["Headphones"])

        if let preset = engine.eqPresets.first {
            engine.deleteEQPreset(preset.id)
        }
        XCTAssertTrue(engine.eqPresets.isEmpty)
    }

    func testRecordingNeedsATap() {
        XCTAssertFalse(
            engine.startRecording(
                "com.a",
                to: FileManager.default.temporaryDirectory.appendingPathComponent("tapmix.wav")
            )
        )
        XCTAssertTrue(engine.recordingBundleIDs.isEmpty)
    }
}
