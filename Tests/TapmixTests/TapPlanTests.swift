import AppKit
import CoreAudio
import XCTest
@testable import TapmixCore

final class TapPlanTests: XCTestCase {
    private func group(
        _ bundleID: String,
        processes: [AudioObjectID],
        playing: [AudioObjectID],
        capturing: [AudioObjectID] = [],
        route: String? = nil
    ) -> AppGroup {
        var level = AppLevel()
        level.outputUID = route
        return AppGroup(
            bundleID: bundleID,
            name: bundleID,
            icon: nil,
            isPlaying: !playing.isEmpty,
            processObjectIDs: processes,
            playingProcessObjectIDs: playing,
            capturingProcessObjectIDs: capturing,
            level: level,
            pinned: false
        )
    }

    func testUnreadableProcessListKeepsTheRunningMix() {
        let plan = TapPlan.make(
            groups: [],
            availableUIDs: ["dev-1"],
            outputUID: "dev-1",
            activeProcessIDs: [7],
            processListReadable: false
        )

        XCTAssertFalse(plan.isComplete)
        XCTAssertTrue(plan.taps.isEmpty)
    }

    func testReadableEmptyListStopsEverything() {
        let plan = TapPlan.make(
            groups: [],
            availableUIDs: ["dev-1"],
            outputUID: "dev-1",
            activeProcessIDs: [],
            processListReadable: true
        )

        XCTAssertTrue(plan.isComplete)
        XCTAssertTrue(plan.taps.isEmpty)
    }

    func testOnlyPlayingOrActiveProcessesGetTaps() {
        let plan = TapPlan.make(
            groups: [group("com.a", processes: [1, 2, 3], playing: [1])],
            availableUIDs: ["dev-1"],
            outputUID: "dev-1",
            activeProcessIDs: [2],
            processListReadable: true
        )

        XCTAssertEqual(plan.taps.map(\.processObjectID), [1, 2])
        XCTAssertEqual(plan.taps.map(\.outputUID), ["dev-1", "dev-1"])
    }

    func testPinnedButIdleAppGetsNoTap() {
        let plan = TapPlan.make(
            groups: [group("com.a", processes: [1], playing: [])],
            availableUIDs: ["dev-1"],
            outputUID: "dev-1",
            activeProcessIDs: [],
            processListReadable: true
        )

        XCTAssertTrue(plan.taps.isEmpty)
    }

    func testMissingRouteFallsBackToTheSystemDefault() {
        let plan = TapPlan.make(
            groups: [group("com.a", processes: [1], playing: [1], route: "gone")],
            availableUIDs: ["dev-1"],
            outputUID: "dev-1",
            activeProcessIDs: [],
            processListReadable: true
        )

        XCTAssertEqual(plan.taps.first?.outputUID, "dev-1")
    }

    func testExplicitRouteWinsWhileItExists() {
        let plan = TapPlan.make(
            groups: [group("com.a", processes: [1], playing: [1], route: "dev-2")],
            availableUIDs: ["dev-1", "dev-2"],
            outputUID: "dev-1",
            activeProcessIDs: [],
            processListReadable: true
        )

        XCTAssertEqual(plan.taps.first?.outputUID, "dev-2")
    }

    func testNoOutputDeviceMeansNoTap() {
        let plan = TapPlan.make(
            groups: [group("com.a", processes: [1], playing: [1])],
            availableUIDs: [],
            outputUID: nil,
            activeProcessIDs: [],
            processListReadable: true
        )

        XCTAssertTrue(plan.isComplete)
        XCTAssertTrue(plan.taps.isEmpty)
    }

    func testProcessInACallPlaysUntouched() {
        let plan = TapPlan.make(
            groups: [group("net.whatsapp.WhatsApp", processes: [1, 2], playing: [1, 2], capturing: [1])],
            availableUIDs: ["dev-1"],
            outputUID: "dev-1",
            activeProcessIDs: [1],
            processListReadable: true
        )

        XCTAssertEqual(plan.taps.map(\.processObjectID), [2])
    }
}
