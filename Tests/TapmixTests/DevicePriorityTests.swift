import XCTest
@testable import TapmixCore

final class DevicePriorityTests: XCTestCase {
    func testActivatesPreferredDeviceWhenItAppears() {
        XCTAssertEqual(
            DevicePriority.outputDeviceToActivate(
                preferredUID: "headphones",
                currentUID: "speakers",
                availableUIDs: ["speakers", "headphones"],
                newlyAvailable: ["headphones"]
            ),
            "headphones"
        )
    }

    func testDoesNotOverrideManualChoiceWhileDeviceStaysConnected() {
        XCTAssertNil(
            DevicePriority.outputDeviceToActivate(
                preferredUID: "headphones",
                currentUID: "speakers",
                availableUIDs: ["speakers", "headphones"],
                newlyAvailable: []
            )
        )
    }

    func testDoesNothingWhenPreferredIsAlreadyDefault() {
        XCTAssertNil(
            DevicePriority.outputDeviceToActivate(
                preferredUID: "headphones",
                currentUID: "headphones",
                availableUIDs: ["headphones"],
                newlyAvailable: ["headphones"]
            )
        )
    }

    func testDoesNothingWhenPreferredIsDisconnected() {
        XCTAssertNil(
            DevicePriority.outputDeviceToActivate(
                preferredUID: "headphones",
                currentUID: "speakers",
                availableUIDs: ["speakers"],
                newlyAvailable: ["speakers"]
            )
        )
    }

    func testFollowsMacOSWithoutPreference() {
        XCTAssertNil(
            DevicePriority.outputDeviceToActivate(
                preferredUID: nil,
                currentUID: "speakers",
                availableUIDs: ["speakers", "headphones"],
                newlyAvailable: ["headphones"]
            )
        )
    }
}
