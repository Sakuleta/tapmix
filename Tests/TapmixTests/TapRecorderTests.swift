import AudioToolbox
import CoreAudio
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

    func testRecordsFromAnInterleavedBufferList() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tapmix-recording-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let frames = 1_000
        let samples = UnsafeMutablePointer<Float>.allocate(capacity: frames * 2)
        let list = AudioBufferList.allocate(maximumBuffers: 1)
        defer {
            samples.deallocate()
            free(list.unsafeMutablePointer)
        }
        for index in 0 ..< frames {
            samples[index * 2] = 0.25
            samples[index * 2 + 1] = -0.25
        }
        list[0] = AudioBuffer(
            mNumberChannels: 2,
            mDataByteSize: UInt32(frames * 2 * MemoryLayout<Float>.size),
            mData: samples
        )

        let recorder = try TapRecorder(url: url, sampleRate: 8_000)
        recorder.write(bufferList: list.unsafeMutablePointer)
        recorder.stop()

        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.count, 44 + frames * 4)
    }

    func testStopsAtTheFrameCeiling() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tapmix-recording-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let recorder = try TapRecorder(url: url, sampleRate: 8_000, maxFrames: 1_000)
        for _ in 0 ..< 2_000 {
            recorder.write(left: 0.25, right: 0.25)
        }
        recorder.stop()

        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.count, 44 + 1_000 * 4)

        let dataSize: UInt32 = data.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 40, as: UInt32.self)
        }
        XCTAssertEqual(dataSize, 1_000 * 4)
    }

    func testSecondStopIsANoOp() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tapmix-recording-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let recorder = try TapRecorder(url: url, sampleRate: 8_000)
        recorder.write(left: 0.1, right: 0.1)
        recorder.stop()
        recorder.stop()

        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.count, 44 + 4)
    }
}
