import XCTest
@testable import TapmixCore

final class AppUpdateTests: XCTestCase {
    func testNewerVersions() {
        XCTAssertTrue(AppUpdate.isNewer("0.2.2", than: "0.2.1"))
        XCTAssertTrue(AppUpdate.isNewer("0.3.0", than: "0.2.9"))
        XCTAssertTrue(AppUpdate.isNewer("v0.2.10", than: "0.2.9"))
        XCTAssertTrue(AppUpdate.isNewer("1.0", than: "0.9.9"))
    }

    func testSameOrOlderVersions() {
        XCTAssertFalse(AppUpdate.isNewer("0.2.1", than: "0.2.1"))
        XCTAssertFalse(AppUpdate.isNewer("0.2.0", than: "0.2.1"))
        XCTAssertFalse(AppUpdate.isNewer("v0.2.1", than: "0.2.1"))
    }

    func testSuffixesAreIgnored() {
        XCTAssertTrue(AppUpdate.isNewer("0.3.0-beta.2", than: "0.2.1"))
        XCTAssertFalse(AppUpdate.isNewer("0.2.1-beta.2", than: "0.2.1"))
    }
}
