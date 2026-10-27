import AppKit
import CoreAudio
import XCTest
@testable import TapmixCore

final class AudioCatalogTests: XCTestCase {
    private func descriptor(
        pid: pid_t,
        bundleID: String,
        name: String,
        regular: Bool,
        prohibited: Bool = false,
        bundlePath: String?,
        executablePath: String?
    ) -> RunningAppDescriptor {
        RunningAppDescriptor(
            pid: pid,
            bundleID: bundleID,
            name: name,
            icon: nil,
            isRegular: regular,
            isProhibited: prohibited,
            bundlePath: bundlePath,
            executablePath: executablePath
        )
    }

    private var braveHost: RunningAppDescriptor {
        descriptor(
            pid: 5,
            bundleID: "com.brave.Browser",
            name: "Brave Browser",
            regular: true,
            bundlePath: "/Applications/Brave Browser.app",
            executablePath: "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
        )
    }

    private var braveHelper: RunningAppDescriptor {
        descriptor(
            pid: 10,
            bundleID: "com.brave.Browser.helper",
            name: "Brave Helper",
            regular: false,
            prohibited: true,
            bundlePath: "/Applications/Brave Browser.app/Contents/Frameworks/Brave Helper.app",
            executablePath: "/Applications/Brave Browser.app/Contents/Frameworks/Brave Helper.app/Contents/MacOS/Brave Helper"
        )
    }

    private func process(
        _ objectID: AudioObjectID,
        pid: pid_t = 10,
        bundleID: String = "com.brave.Browser.helper",
        playing: Bool = true,
        capturing: Bool = false,
        executablePath: String? = nil
    ) -> AudioProcess {
        AudioProcess(
            objectID: objectID,
            pid: pid,
            bundleID: bundleID,
            isPlaying: playing,
            isCapturing: capturing,
            executablePath: executablePath
        )
    }

    private func groups(
        processes: [AudioProcess],
        running: [RunningAppDescriptor],
        levels: [String: AppLevel] = [:],
        active: Set<String> = [],
        pinned: Set<String> = [],
        ignored: Set<String> = []
    ) -> [AppGroup] {
        AudioCatalog.groups(
            processes: processes,
            running: running,
            levels: levels,
            activeBundleIDs: active,
            pinnedBundleIDs: pinned,
            ignoredBundleIDs: ignored
        )
    }

    func testHelperMapsToHost() {
        let result = groups(processes: [process(1)], running: [braveHost, braveHelper])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.bundleID, "com.brave.Browser")
        XCTAssertEqual(result.first?.name, "Brave Browser")
        XCTAssertEqual(result.first?.playingProcessObjectIDs, [1])
    }

    func testUnregisteredHelperMapsByProcessPath() {
        // The audio helper is not in NSWorkspace.runningApplications, so only
        // proc_pidpath can reveal that it lives inside the host bundle.
        let helper = process(
            1,
            pid: 10,
            executablePath: "/Applications/Brave Browser.app/Contents/Frameworks/Brave Browser Framework.framework/Versions/156/Helpers/Brave Browser Helper.app/Contents/MacOS/Brave Browser Helper"
        )
        let result = groups(processes: [helper], running: [braveHost])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.bundleID, "com.brave.Browser")
        XCTAssertEqual(result.first?.playingProcessObjectIDs, [1])
    }

    func testCapturingProcessMarksTheRowInACall() {
        let result = groups(
            processes: [process(1, capturing: true), process(2)],
            running: [braveHost, braveHelper]
        )

        XCTAssertEqual(result.first?.capturingProcessObjectIDs, [1])
        XCTAssertEqual(result.first?.row.isInCall, true)
    }

    func testOrphanHelperIsHidden() {
        XCTAssertTrue(groups(processes: [process(1)], running: [braveHelper]).isEmpty)
    }

    func testIgnoredBundleIsHidden() {
        let host = descriptor(
            pid: 5,
            bundleID: "com.apple.coreaudio",
            name: "coreaudiod",
            regular: true,
            bundlePath: "/System/Library/CoreServices/coreaudiod.app",
            executablePath: "/System/Library/CoreServices/coreaudiod.app/Contents/MacOS/coreaudiod"
        )
        let audio = process(1, pid: 5, bundleID: "com.apple.coreaudio")
        XCTAssertTrue(groups(processes: [audio], running: [host]).isEmpty)
    }

    func testOwnBundleIsHidden() {
        let host = descriptor(
            pid: 5,
            bundleID: "com.mardinli.tapmix",
            name: "Tapmix",
            regular: true,
            bundlePath: "/Applications/Tapmix.app",
            executablePath: "/Applications/Tapmix.app/Contents/MacOS/Tapmix"
        )
        let own = process(1, pid: 5, bundleID: "com.mardinli.tapmix")
        XCTAssertTrue(groups(processes: [own], running: [host]).isEmpty)
    }

    func testPlayingAppAppearsWithoutStoredLevel() {
        let result = groups(
            processes: [process(1, pid: 5, bundleID: "com.brave.Browser")],
            running: [braveHost]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].isPlaying)
    }

    func testStoredLevelKeepsIdleApp() {
        let result = groups(
            processes: [process(1, pid: 5, bundleID: "com.brave.Browser", playing: false)],
            running: [braveHost],
            levels: ["com.brave.Browser": AppLevel(volume: 0.4)]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result[0].isPlaying)
        XCTAssertEqual(result[0].level.volume, 0.4, accuracy: 0.0001)
        XCTAssertEqual(result[0].row.volume, 0.4, accuracy: 0.0001)
    }

    func testActiveTapKeepsIdleApp() {
        let result = groups(
            processes: [process(1, pid: 5, bundleID: "com.brave.Browser", playing: false)],
            running: [braveHost],
            active: ["com.brave.Browser"]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result[0].isPlaying)
    }

    func testTwoHelpersMergeUnderHost() {
        let helper2 = descriptor(
            pid: 11,
            bundleID: "com.brave.Browser.helper.renderer",
            name: "Brave Helper (Renderer)",
            regular: false,
            prohibited: true,
            bundlePath: "/Applications/Brave Browser.app/Contents/Frameworks/Brave Helper.app",
            executablePath: "/Applications/Brave Browser.app/Contents/Frameworks/Brave Helper.app/Contents/MacOS/Brave Helper"
        )
        let result = groups(
            processes: [process(1), process(2, pid: 11)],
            running: [braveHost, braveHelper, helper2]
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].processObjectIDs.sorted(), [1, 2])
        XCTAssertEqual(result[0].playingProcessObjectIDs.sorted(), [1, 2])
    }

    func testRowsSortByLocalizedName() {
        let alpha = descriptor(
            pid: 7,
            bundleID: "com.example.alpha",
            name: "Alpha",
            regular: true,
            bundlePath: "/Applications/Alpha.app",
            executablePath: "/Applications/Alpha.app/Contents/MacOS/Alpha"
        )
        let zebra = descriptor(
            pid: 8,
            bundleID: "com.example.zebra",
            name: "Zebra",
            regular: true,
            bundlePath: "/Applications/Zebra.app",
            executablePath: "/Applications/Zebra.app/Contents/MacOS/Zebra"
        )
        let result = groups(
            processes: [
                process(1, pid: 8, bundleID: "com.example.zebra"),
                process(2, pid: 7, bundleID: "com.example.alpha")
            ],
            running: [zebra, alpha]
        )
        XCTAssertEqual(result.map(\.name), ["Alpha", "Zebra"])
    }

    func testPinnedIdleAppAppears() {
        let result = groups(
            processes: [process(1, pid: 5, bundleID: "com.brave.Browser", playing: false)],
            running: [braveHost],
            pinned: ["com.brave.Browser"]
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].pinned)
        XCTAssertFalse(result[0].isPlaying)
        XCTAssertTrue(result[0].row.pinned)
    }

    func testIgnoredAppIsHidden() {
        let result = groups(
            processes: [process(1, pid: 5, bundleID: "com.brave.Browser")],
            running: [braveHost],
            levels: ["com.brave.Browser": AppLevel(volume: 0.5)],
            active: ["com.brave.Browser"],
            ignored: ["com.brave.Browser"]
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testPinnedAppsSortFirst() {
        let alpha = descriptor(
            pid: 7,
            bundleID: "com.example.alpha",
            name: "Alpha",
            regular: true,
            bundlePath: "/Applications/Alpha.app",
            executablePath: "/Applications/Alpha.app/Contents/MacOS/Alpha"
        )
        let zebra = descriptor(
            pid: 8,
            bundleID: "com.example.zebra",
            name: "Zebra",
            regular: true,
            bundlePath: "/Applications/Zebra.app",
            executablePath: "/Applications/Zebra.app/Contents/MacOS/Zebra"
        )
        let result = groups(
            processes: [
                process(1, pid: 7, bundleID: "com.example.alpha"),
                process(2, pid: 8, bundleID: "com.example.zebra")
            ],
            running: [alpha, zebra],
            pinned: ["com.example.zebra"]
        )
        XCTAssertEqual(result.map(\.name), ["Zebra", "Alpha"])
    }

    func testIdleAppWithoutLevelOrTapIsHidden() {
        let result = groups(
            processes: [process(1, pid: 5, bundleID: "com.brave.Browser", playing: false)],
            running: [braveHost]
        )
        XCTAssertTrue(result.isEmpty)
    }
}
