import XCTest
@testable import TapmixCore

final class TapmixURLCommandTests: XCTestCase {
    private func parse(_ string: String) -> TapmixURLCommand? {
        guard let url = URL(string: string) else { return nil }
        return TapmixURLCommand.parse(url)
    }

    func testSetVolumePercent() {
        XCTAssertEqual(
            parse("tapmix://set-volume?app=com.brave.Browser&volume=75"),
            .setVolume(bundleID: "com.brave.Browser", volume: 0.75)
        )
    }

    func testSetVolumeClamps() {
        XCTAssertEqual(
            parse("tapmix://set-volume?app=com.a&volume=300"),
            .setVolume(bundleID: "com.a", volume: 2)
        )
    }

    func testStepVolumeDefaultsToFivePercent() {
        XCTAssertEqual(
            parse("tapmix://step-volume?app=com.a"),
            .stepVolume(bundleID: "com.a", delta: 0.05)
        )
    }

    func testStepVolumeNegative() {
        XCTAssertEqual(
            parse("tapmix://step-volume?app=com.a&delta=-10"),
            .stepVolume(bundleID: "com.a", delta: -0.1)
        )
    }

    func testMuteFlag() {
        XCTAssertEqual(
            parse("tapmix://set-mute?app=com.a&muted=true"),
            .setMute(bundleID: "com.a", muted: true)
        )
        XCTAssertEqual(
            parse("tapmix://set-mute?app=com.a&muted=0"),
            .setMute(bundleID: "com.a", muted: false)
        )
    }

    func testToggleMute() {
        XCTAssertEqual(
            parse("tapmix://toggle-mute?app=com.a"),
            .toggleMute(bundleID: "com.a")
        )
    }

    func testBoostClamps() {
        XCTAssertEqual(
            parse("tapmix://set-boost?app=com.a&boost=9"),
            .setBoost(bundleID: "com.a", boost: 4)
        )
    }

    func testRouteDeviceIsDecodedAndOptional() {
        XCTAssertEqual(
            parse("tapmix://set-route?app=com.a&device=ABC%20DEF"),
            .setRoute(bundleID: "com.a", deviceUID: "ABC DEF")
        )
        XCTAssertEqual(
            parse("tapmix://set-route?app=com.a&device="),
            .setRoute(bundleID: "com.a", deviceUID: nil)
        )
    }

    func testRejectsUnknownOrIncompleteCommands() {
        XCTAssertNil(parse("https://set-volume?app=com.a&volume=50"))
        XCTAssertNil(parse("tapmix://unknown?app=com.a"))
        XCTAssertNil(parse("tapmix://set-volume?volume=50"))
        XCTAssertNil(parse("tapmix://set-volume?app=com.a"))
    }
}
