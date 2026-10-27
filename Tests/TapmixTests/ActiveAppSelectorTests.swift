import XCTest
@testable import TapmixCore

final class ActiveAppSelectorTests: XCTestCase {
    private func app(
        _ bundleID: String,
        playing: Bool = false,
        level: Float = 0
    ) -> AppRow {
        AppRow(
            bundleID: bundleID,
            name: bundleID,
            icon: nil,
            isPlaying: playing,
            volume: 1,
            muted: false,
            level: level
        )
    }

    func testEmptyListReturnsNil() {
        XCTAssertNil(ActiveAppSelector.bundleID(apps: [], frontmost: nil, lastActive: nil))
    }

    func testPlayingAppWins() {
        let apps = [app("com.idle"), app("com.playing", playing: true)]
        XCTAssertEqual(
            ActiveAppSelector.bundleID(apps: apps, frontmost: "com.idle", lastActive: nil),
            "com.playing"
        )
    }

    func testLastActivePlayingAppWins() {
        let apps = [
            app("com.a", playing: true, level: 0.4),
            app("com.b", playing: true, level: 0.9)
        ]
        XCTAssertEqual(
            ActiveAppSelector.bundleID(apps: apps, frontmost: nil, lastActive: "com.a"),
            "com.a"
        )
    }

    func testLoudestPlayingAppWinsWithoutHistory() {
        let apps = [
            app("com.a", playing: true, level: 0.4),
            app("com.b", playing: true, level: 0.9)
        ]
        XCTAssertEqual(
            ActiveAppSelector.bundleID(apps: apps, frontmost: nil, lastActive: nil),
            "com.b"
        )
    }

    func testFrontmostAppWhenNothingPlays() {
        let apps = [app("com.a"), app("com.b")]
        XCTAssertEqual(
            ActiveAppSelector.bundleID(apps: apps, frontmost: "com.b", lastActive: "com.a"),
            "com.b"
        )
    }

    func testLastActiveAppWhenFrontmostIsNotListed() {
        let apps = [app("com.a"), app("com.b")]
        XCTAssertEqual(
            ActiveAppSelector.bundleID(apps: apps, frontmost: "com.other", lastActive: "com.b"),
            "com.b"
        )
    }

    func testFirstAppAsFinalFallback() {
        let apps = [app("com.a"), app("com.b")]
        XCTAssertEqual(
            ActiveAppSelector.bundleID(apps: apps, frontmost: nil, lastActive: nil),
            "com.a"
        )
    }
}
