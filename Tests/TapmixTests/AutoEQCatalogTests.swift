import XCTest
@testable import TapmixCore

final class AutoEQCatalogTests: XCTestCase {
    func testScanAndLoad() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tapmix-autoeq-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let model = root.appendingPathComponent("results/Sony WH-1000XM5")
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        try """
        Preamp: -6.0 dB
        Filter 1: ON PK Fc 1000 Hz Gain 3.0 dB Q 1.0
        Filter 2: ON LSC Fc 100 Hz Gain 5.0 dB Q 0.7
        """.write(
            to: model.appendingPathComponent("ParametricEQ.txt"),
            atomically: true,
            encoding: .utf8
        )

        let profiles = AutoEQCatalog.scan(folder: root)
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles[0].name, "Sony WH-1000XM5")
        XCTAssertEqual(AutoEQCatalog.filters(for: profiles[0]).count, 2)
    }

    func testMissingFolderIsEmpty() {
        let missing = URL(fileURLWithPath: "/tmp/tapmix-autoeq-missing-\(UUID().uuidString)")
        XCTAssertTrue(AutoEQCatalog.scan(folder: missing).isEmpty)
    }
}
