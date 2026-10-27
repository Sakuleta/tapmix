import XCTest
@testable import TapmixCore

final class EQResponseTests: XCTestCase {
    func testFlatResponseIsSilent() {
        let points = EQResponse.points(for: EQSettings(enabled: true))
        XCTAssertEqual(points.count, 120)
        for point in points {
            XCTAssertEqual(point, 0, accuracy: 0.001)
        }
    }

    func testSingleBandPeaksAtItsCenter() {
        var gains = [Float](repeating: 0, count: EQSettings.bandCount)
        gains[5] = 6
        let settings = EQSettings(enabled: true, gains: gains)

        XCTAssertEqual(EQResponse.decibels(at: 1_000, settings: settings), 6, accuracy: 0.2)
        XCTAssertEqual(EQResponse.decibels(at: 100, settings: settings), 0, accuracy: 0.5)
    }

    func testImportedFiltersApplyWithoutBands() {
        let settings = EQSettings(
            enabled: false,
            filters: [EQFilter(kind: .peaking, frequency: 1_000, gainDB: 6, q: 1.4)]
        )
        XCTAssertEqual(EQResponse.decibels(at: 1_000, settings: settings), 6, accuracy: 0.2)
    }

    func testDisabledSettingsHaveFlatCurve() {
        let points = EQResponse.points(for: EQSettings())
        for point in points {
            XCTAssertEqual(point, 0, accuracy: 0.001)
        }
    }
}
