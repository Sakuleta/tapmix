import AudioToolbox
import XCTest
@testable import TapmixCore

final class AudioUnitHostTests: XCTestCase {
    func testCatalogListsSystemEffects() {
        let effects = AudioUnitCatalog.effects()
        XCTAssertFalse(effects.isEmpty)
        XCTAssertEqual(Set(effects.map(\.id)).count, effects.count)
    }

    func testHostsADelayAndKeepsOutputInRange() throws {
        let selection = AudioUnitSelection(
            componentSubType: UInt32(kAudioUnitSubType_Delay),
            componentManufacturer: UInt32(kAudioUnitManufacturer_Apple)
        )
        guard AudioUnitCatalog.effects().contains(where: { $0.selection == selection }) else {
            throw XCTSkip("The Apple delay Audio Unit is not installed")
        }

        let host = try AudioUnitHost(selection: selection, sampleRate: 48_000)
        let frames = 256
        let list = AudioBufferList.allocate(maximumBuffers: 2)
        let left = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        defer {
            left.deallocate()
            right.deallocate()
            free(list.unsafeMutablePointer)
        }
        for index in 0 ..< frames {
            left[index] = sin(Float(index) * 0.05) * 0.5
            right[index] = left[index]
        }
        list[0] = AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: UInt32(frames * 4),
            mData: left
        )
        list[1] = AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: UInt32(frames * 4),
            mData: right
        )
        let input = Array(UnsafeBufferPointer(start: left, count: frames))

        host.process(bufferList: list.unsafeMutablePointer)

        for index in 0 ..< frames {
            XCTAssertTrue(left[index].isFinite)
            XCTAssertTrue(right[index].isFinite)
            XCTAssertLessThanOrEqual(abs(left[index]), 1)
            XCTAssertLessThanOrEqual(abs(right[index]), 1)
        }

        // A 50% wet delay cannot return the dry signal unchanged; if nothing
        // differs the unit never rendered.
        let changed = (0 ..< frames).contains { abs(left[$0] - input[$0]) > 0.001 }
        XCTAssertTrue(changed, "The Audio Unit did not process the buffer")
    }

    func testInterleavedBufferIsProcessedInPlace() throws {
        let selection = AudioUnitSelection(
            componentSubType: UInt32(kAudioUnitSubType_Delay),
            componentManufacturer: UInt32(kAudioUnitManufacturer_Apple)
        )
        guard AudioUnitCatalog.effects().contains(where: { $0.selection == selection }) else {
            throw XCTSkip("The Apple delay Audio Unit is not installed")
        }

        let host = try AudioUnitHost(selection: selection, sampleRate: 48_000)
        let frames = 128
        let list = AudioBufferList.allocate(maximumBuffers: 1)
        let samples = UnsafeMutablePointer<Float>.allocate(capacity: frames * 2)
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
            mDataByteSize: UInt32(frames * 2 * 4),
            mData: samples
        )

        host.process(bufferList: list.unsafeMutablePointer)

        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].mNumberChannels, 2)
        XCTAssertTrue(samples[0].isFinite)
        XCTAssertTrue(samples[frames * 2 - 1].isFinite)
    }
}
