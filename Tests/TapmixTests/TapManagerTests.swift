import CoreAudio
import Foundation
import XCTest
@testable import TapmixCore

private struct TestError: LocalizedError {
    var errorDescription: String? { "Tap failed to start." }
}

final class FakeTap: TapControlling {
    let processObjectID: AudioObjectID
    let bundleID: String
    let createdAt: Date
    var callbackCount: UInt64 = 1
    var peak: Float = 0
    var startError: Error?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var gain: Float = 1

    init(processObjectID: AudioObjectID, bundleID: String, createdAt: Date) {
        self.processObjectID = processObjectID
        self.bundleID = bundleID
        self.createdAt = createdAt
    }

    func start() throws {
        startCount += 1
        if let startError { throw startError }
    }
    func stop() { stopCount += 1 }
    func setGain(_ gain: Float) { self.gain = gain }
    func takePeakLevel() -> Float {
        defer { peak = 0 }
        return peak
    }
}

@MainActor
final class TapManagerTests: XCTestCase {
    private var now = Date(timeIntervalSinceReferenceDate: 0)
    private var manager: TapManager!
    private var created: [FakeTap] = []
    private var outputUIDs: [String] = []
    private var failing: Set<AudioObjectID> = []

    override func setUp() {
        super.setUp()
        now = Date(timeIntervalSinceReferenceDate: 0)
        created = []
        outputUIDs = []
        failing = []
        manager = TapManager(
            makeTap: { [unowned self] processID, bundleID, outputUID in
                let tap = FakeTap(
                    processObjectID: processID,
                    bundleID: bundleID,
                    createdAt: self.now
                )
                if self.failing.contains(processID) {
                    tap.startError = TestError()
                }
                self.created.append(tap)
                self.outputUIDs.append(outputUID)
                return tap
            },
            now: { [unowned self] in self.now }
        )
    }

    private func desired(_ id: AudioObjectID, _ bundleID: String, _ name: String = "App") -> TapManager.DesiredTap {
        TapManager.DesiredTap(processObjectID: id, bundleID: bundleID, displayName: name)
    }

    private func sync(_ taps: [TapManager.DesiredTap], output: String = "dev-1") {
        manager.sync(desired: taps, outputUID: output)
    }

    func testSyncStartsOneTapPerDesiredProcess() {
        let a = desired(1, "com.a")
        let b = desired(2, "com.b")

        sync([a, b])
        XCTAssertEqual(created.count, 2)
        XCTAssertEqual(created.map(\.startCount), [1, 1])

        sync([a, b])
        XCTAssertEqual(created.count, 2)
        XCTAssertEqual(created.map(\.startCount), [1, 1])
    }

    func testRemovedProcessIsStoppedAndCanReturn() {
        let a = desired(1, "com.a")

        sync([a])
        XCTAssertEqual(created[0].stopCount, 0)

        sync([])
        XCTAssertEqual(created[0].stopCount, 1)
        XCTAssertEqual(manager.activeProcessIDs, [])

        sync([a])
        XCTAssertEqual(created.count, 2)
        XCTAssertEqual(created[1].startCount, 1)
    }

    func testStalledTapStopsOnlyItself() {
        let a = desired(1, "com.a", "App A")
        let b = desired(2, "com.b", "App B")

        sync([a, b])
        created[0].callbackCount = 0
        created[1].callbackCount = 1
        now = now.addingTimeInterval(7)

        sync([a, b])

        XCTAssertEqual(created[0].stopCount, 1)
        XCTAssertEqual(created[1].stopCount, 0)
        XCTAssertTrue(manager.activeProcessIDs.contains(2))
        guard case let .stalled(name, message) = manager.health else {
            return XCTFail("Expected stalled health, got \(manager.health)")
        }
        XCTAssertEqual(name, "App A")
        XCTAssertTrue(message.contains("No audio is arriving."))
    }

    func testNoStallBeforeWindow() {
        let a = desired(1, "com.a")
        let b = desired(2, "com.b")

        sync([a, b])
        created[0].callbackCount = 0
        created[1].callbackCount = 0
        now = now.addingTimeInterval(5)

        sync([a, b])

        XCTAssertEqual(created.map(\.stopCount), [0, 0])
        XCTAssertEqual(manager.health, .ok)
    }

    func testRetryClearsHealthAndRecreates() {
        let a = desired(1, "com.a")
        let b = desired(2, "com.b")

        sync([a, b])
        created[0].callbackCount = 0
        now = now.addingTimeInterval(7)
        sync([a, b])
        guard case .stalled = manager.health else {
            return XCTFail("Expected stalled health before retry")
        }

        manager.retry()
        XCTAssertEqual(manager.health, .ok)

        sync([a, b])
        XCTAssertEqual(created.count, 3)
        XCTAssertEqual(created[2].processObjectID, 1)
        XCTAssertEqual(created[1].stopCount, 0)
        XCTAssertEqual(manager.health, .ok)
    }

    func testStartFailureUsesBackoff() {
        let a = desired(1, "com.a")
        failing = [1]

        sync([a])
        XCTAssertEqual(created.count, 1)
        guard case .stalled = manager.health else {
            return XCTFail("Expected stalled health after a start error")
        }

        now = now.addingTimeInterval(14)
        sync([a])
        XCTAssertEqual(created.count, 1)

        now = now.addingTimeInterval(1)
        sync([a])
        XCTAssertEqual(created.count, 2)
    }

    func testOutputDeviceChangeRebuildsAll() {
        let a = desired(1, "com.a")

        sync([a], output: "dev-1")
        XCTAssertEqual(outputUIDs, ["dev-1"])

        sync([a], output: "dev-2")
        XCTAssertEqual(created.count, 2)
        XCTAssertEqual(created[0].stopCount, 1)
        XCTAssertEqual(outputUIDs, ["dev-1", "dev-2"])
        XCTAssertEqual(manager.activeProcessIDs, [1])
    }

    func testGainAppliesToExistingAndNewTaps() {
        let a = desired(1, "com.a")
        let b = desired(2, "com.b")

        manager.setGain(0.5, for: "com.a")
        sync([a])
        XCTAssertEqual(created[0].gain, 0.5)

        manager.setGain(0, for: "com.a")
        XCTAssertEqual(created[0].gain, 0)

        manager.setGain(0, for: "com.b")
        sync([a, b])
        XCTAssertEqual(created[1].gain, 0)
    }

    func testPeakLevelAggregatesAndResets() {
        let a = desired(1, "com.a")
        let b = desired(2, "com.a")
        sync([a, b])

        created[0].peak = 0.4
        created[1].peak = 0.8
        XCTAssertEqual(manager.peakLevel(for: "com.a"), 0.8, accuracy: 0.0001)
        XCTAssertEqual(manager.peakLevel(for: "com.a"), 0, accuracy: 0.0001)
        XCTAssertEqual(manager.peakLevel(for: "com.b"), 0, accuracy: 0.0001)
    }

    func testHealthyTapSurvivesAnotherStartFailure() {
        let a = desired(1, "com.a", "App A")
        let b = desired(2, "com.b", "App B")
        failing = [1]

        sync([a, b])

        XCTAssertEqual(manager.activeProcessIDs, [2])
        XCTAssertEqual(created[1].stopCount, 0)
        guard case let .stalled(name, _) = manager.health else {
            return XCTFail("Expected stalled health, got \(manager.health)")
        }
        XCTAssertEqual(name, "App A")
    }
}
