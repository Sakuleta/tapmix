import XCTest
@testable import TapmixCore

final class TapRecorderTests: XCTestCase {
    func testRecordsStereoWAV() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tapmix-recording-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let recorder = try TapRecorder(url: url, sampleRate: 8_000)
        for _ in 0 ..< 8_000 {
            recorder.write(left: 0.5, right: -0.5)
        }
        recorder.stop()

        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.count, 44 + 8_000 * 4)
        XCTAssertEqual(String(data: data[0 ..< 4], encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data[8 ..< 12], encoding: .ascii), "WAVE")

        let dataSize: UInt32 = data.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 40, as: UInt32.self)
        }
        XCTAssertEqual(dataSize, 8_000 * 4)

        let first: Int16 = data.withUnsafeBytes {
            Int16(bitPattern: $0.loadUnaligned(fromByteOffset: 44, as: UInt16.self))
        }
        let second: Int16 = data.withUnsafeBytes {
            Int16(bitPattern: $0.loadUnaligned(fromByteOffset: 46, as: UInt16.self))
        }
        XCTAssertEqual(first, 16_383)
        XCTAssertEqual(second, -16_383)
    }
}
