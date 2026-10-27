import XCTest
@testable import TapmixCore

final class DuckingPolicyTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 1000)

    func testDucksForACallAppAfterDelay() {
        var policy = DuckingPolicy()

        XCTAssertFalse(policy.update(inputBundleIDs: ["us.zoom.xos"], now: start))
        XCTAssertFalse(policy.update(inputBundleIDs: ["us.zoom.xos"], now: start + 0.9))
        XCTAssertTrue(policy.update(inputBundleIDs: ["us.zoom.xos"], now: start + 1.1))
    }

    func testReleaseDelay() {
        var policy = DuckingPolicy()
        _ = policy.update(inputBundleIDs: ["us.zoom.xos"], now: start)
        _ = policy.update(inputBundleIDs: ["us.zoom.xos"], now: start + 1.1)

        XCTAssertTrue(policy.update(inputBundleIDs: [], now: start + 2.0))
        XCTAssertTrue(policy.update(inputBundleIDs: [], now: start + 3.4))
        XCTAssertFalse(policy.update(inputBundleIDs: [], now: start + 3.6))
    }

    func testMicrophoneRestartDuringReleaseKeepsDucking() {
        var policy = DuckingPolicy()
        _ = policy.update(inputBundleIDs: ["us.zoom.xos"], now: start)
        _ = policy.update(inputBundleIDs: ["us.zoom.xos"], now: start + 1.1)
        _ = policy.update(inputBundleIDs: [], now: start + 2.0)

        XCTAssertTrue(policy.update(inputBundleIDs: ["us.zoom.xos"], now: start + 2.5))
    }

    func testRecorderHoldingTheMicrophoneDoesNotDuck() {
        var policy = DuckingPolicy()

        for offset in stride(from: 0.0, through: 30.0, by: 1.0) {
            XCTAssertFalse(
                policy.update(inputBundleIDs: ["com.kitlangton.hex2"], now: start + offset)
            )
        }
        XCTAssertFalse(policy.isExempt(bundleID: "com.kitlangton.hex2"))
    }

    func testBrowserCallDucks() {
        var policy = DuckingPolicy()

        XCTAssertFalse(policy.update(inputBundleIDs: ["com.brave.Browser"], now: start))
        XCTAssertTrue(policy.update(inputBundleIDs: ["com.brave.Browser"], now: start + 1.1))
        XCTAssertTrue(policy.isExempt(bundleID: "com.brave.Browser"))
    }

    func testACallAppWinsOverAnotherMicrophoneUser() {
        var policy = DuckingPolicy()
        let users: Set<String> = ["com.kitlangton.hex2", "com.microsoft.teams2"]

        XCTAssertFalse(policy.update(inputBundleIDs: users, now: start))
        XCTAssertTrue(policy.update(inputBundleIDs: users, now: start + 1.1))
        XCTAssertTrue(policy.isExempt(bundleID: "com.microsoft.teams2"))
    }

    func testCallAppAndKnownAppsAreExempt() {
        var policy = DuckingPolicy()
        _ = policy.update(inputBundleIDs: ["us.zoom.xos"], now: start)

        XCTAssertTrue(policy.isExempt(bundleID: "us.zoom.xos"))
        XCTAssertTrue(policy.isExempt(bundleID: "com.apple.FaceTime"))
        XCTAssertFalse(policy.isExempt(bundleID: "com.brave.Browser"))
    }

    func testResetClearsDucking() {
        var policy = DuckingPolicy()
        _ = policy.update(inputBundleIDs: ["us.zoom.xos"], now: start)
        _ = policy.update(inputBundleIDs: ["us.zoom.xos"], now: start + 1.1)
        policy.reset()

        XCTAssertFalse(policy.isDucking)
        XCTAssertFalse(policy.isExempt(bundleID: "us.zoom.xos") && policy.isDucking)
    }

    func testNoDuckingWithoutCallInput() {
        var policy = DuckingPolicy()
        XCTAssertFalse(policy.update(inputBundleIDs: [], now: start))
    }
}
