import XCTest
@testable import TapmixCore

final class DuckingPolicyTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 1000)

    func testDucksAfterDelay() {
        var policy = DuckingPolicy()

        XCTAssertFalse(policy.update(micActive: true, frontmost: "us.zoom.xos", now: start))
        XCTAssertFalse(policy.update(micActive: true, frontmost: "us.zoom.xos", now: start + 0.9))
        XCTAssertTrue(policy.update(micActive: true, frontmost: "us.zoom.xos", now: start + 1.1))
    }

    func testReleaseDelay() {
        var policy = DuckingPolicy()
        _ = policy.update(micActive: true, frontmost: "us.zoom.xos", now: start)
        _ = policy.update(micActive: true, frontmost: "us.zoom.xos", now: start + 1.1)

        XCTAssertTrue(policy.update(micActive: false, frontmost: "us.zoom.xos", now: start + 2.0))
        XCTAssertTrue(policy.update(micActive: false, frontmost: "us.zoom.xos", now: start + 3.4))
        XCTAssertFalse(policy.update(micActive: false, frontmost: "us.zoom.xos", now: start + 3.6))
    }

    func testMicrophoneRestartDuringReleaseKeepsDucking() {
        var policy = DuckingPolicy()
        _ = policy.update(micActive: true, frontmost: "us.zoom.xos", now: start)
        _ = policy.update(micActive: true, frontmost: "us.zoom.xos", now: start + 1.1)
        _ = policy.update(micActive: false, frontmost: "us.zoom.xos", now: start + 2.0)

        XCTAssertTrue(policy.update(micActive: true, frontmost: "us.zoom.xos", now: start + 2.5))
    }

    func testCallAppAndKnownAppsAreExempt() {
        var policy = DuckingPolicy()
        _ = policy.update(micActive: true, frontmost: "com.example.call", now: start)

        XCTAssertTrue(policy.isExempt(bundleID: "com.example.call"))
        XCTAssertTrue(policy.isExempt(bundleID: "us.zoom.xos"))
        XCTAssertFalse(policy.isExempt(bundleID: "com.brave.Browser"))
    }

    func testResetClearsDucking() {
        var policy = DuckingPolicy()
        _ = policy.update(micActive: true, frontmost: "us.zoom.xos", now: start)
        _ = policy.update(micActive: true, frontmost: "us.zoom.xos", now: start + 1.1)
        policy.reset()

        XCTAssertFalse(policy.isDucking)
        XCTAssertFalse(policy.isExempt(bundleID: "com.example.call"))
    }

    func testNoDuckingWhenMicrophoneWasNeverActive() {
        var policy = DuckingPolicy()
        XCTAssertFalse(policy.update(micActive: false, frontmost: "us.zoom.xos", now: start))
    }
}
