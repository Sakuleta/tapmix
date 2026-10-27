import XCTest
@testable import TapmixCore

final class AudioSystemTests: XCTestCase {
    func testMainElementWinsWhenPresent() {
        XCTAssertEqual(AudioSystem.combinedMute(main: true, channels: [false, false]), true)
        XCTAssertEqual(AudioSystem.combinedMute(main: false, channels: [true, true]), false)
    }

    func testAllChannelsMuted() {
        XCTAssertEqual(AudioSystem.combinedMute(main: nil, channels: [true, true]), true)
    }

    func testPartialChannelMuteIsNotFullyMuted() {
        XCTAssertEqual(AudioSystem.combinedMute(main: nil, channels: [true, false]), false)
    }

    func testMonoChannelMute() {
        XCTAssertEqual(AudioSystem.combinedMute(main: nil, channels: [true]), true)
    }

    func testNoMuteProperty() {
        XCTAssertNil(AudioSystem.combinedMute(main: nil, channels: []))
    }
}
