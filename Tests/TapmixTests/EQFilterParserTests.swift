import XCTest
@testable import TapmixCore

final class EQFilterParserTests: XCTestCase {
    func testParsesAutoEQFile() {
        let text = """
        Preamp: -6.2 dB
        Filter 1: ON PK Fc 105 Hz Gain 3.0 dB Q 0.70
        Filter 2: ON LSC Fc 20 Hz Gain 5.5 dB Q 0.71
        Filter 3: ON HSC Fc 10000 Hz Gain -2.0 dB Q 0.70

        # comment
        """

        let filters = EQFilterParser.parse(text)
        XCTAssertEqual(filters.count, 3)
        XCTAssertEqual(filters[0].kind, .peaking)
        XCTAssertEqual(filters[0].frequency, 105, accuracy: 0.001)
        XCTAssertEqual(filters[0].gainDB, 3, accuracy: 0.001)
        XCTAssertEqual(filters[1].kind, .lowShelf)
        XCTAssertEqual(filters[1].frequency, 20, accuracy: 0.001)
        XCTAssertEqual(filters[2].kind, .highShelf)
        XCTAssertEqual(filters[2].gainDB, -2, accuracy: 0.001)
    }

    func testSkipsInvalidLines() {
        let text = """
        Filter 1: ON PK Fc 1000 Hz Gain 3.0 dB Q 1.0
        nonsense
        Filter 2: ON PK Fc 1000 Hz
        Preamp: -3 dB
        """

        let filters = EQFilterParser.parse(text)
        XCTAssertEqual(filters.count, 1)
    }

    func testCapsFilterCount() {
        let lines = (1 ... 40).map { "Filter \($0): ON PK Fc 1000 Hz Gain 3.0 dB Q 1.0" }
        let filters = EQFilterParser.parse(lines.joined(separator: "\n"))
        XCTAssertEqual(filters.count, EQFilterParser.maxFilters)
    }

    func testDefaultsMissingQ() {
        let text = "Filter 1: ON PK Fc 500 Hz Gain 2.0 dB"
        let filters = EQFilterParser.parse(text)
        XCTAssertEqual(filters.first?.q ?? 0, 0.707, accuracy: 0.0001)
    }
}
