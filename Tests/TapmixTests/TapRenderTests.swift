import AudioToolbox
import CoreAudio
import Foundation
import XCTest
@testable import TapmixCore

final class TestBufferList {
    let list: UnsafeMutableAudioBufferListPointer
    private var storage: [UnsafeMutableRawPointer] = []

    init(channels: [Int], frames: Int) {
        list = AudioBufferList.allocate(maximumBuffers: channels.count)
        for (index, channelCount) in channels.enumerated() {
            let byteCount = frames * channelCount * MemoryLayout<Float>.size
            let data = UnsafeMutableRawPointer.allocate(
                byteCount: byteCount,
                alignment: MemoryLayout<Float>.alignment
            )
            memset(data, 0, byteCount)
            storage.append(data)
            list[index] = AudioBuffer(
                mNumberChannels: UInt32(channelCount),
                mDataByteSize: UInt32(byteCount),
                mData: data
            )
        }
    }

    func write(_ samples: [Float], at index: Int) {
        let buffer = list[index]
        guard let destination = buffer.mData else { return }
        samples.withUnsafeBytes { bytes in
            memcpy(destination, bytes.baseAddress, bytes.count)
        }
    }

    func read(at index: Int) -> [Float] {
        let buffer = list[index]
        guard let data = buffer.mData else { return [] }
        let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        return Array(UnsafeBufferPointer(
            start: data.assumingMemoryBound(to: Float.self),
            count: count
        ))
    }

    deinit {
        for data in storage { data.deallocate() }
        free(list.unsafeMutablePointer)
    }
}

final class TapRenderTests: XCTestCase {
    private func render(
        input: TestBufferList,
        output: TestBufferList,
        plan: TapRenderPlan,
        targetGain: Float,
        coefficient: Float,
        gain: inout Float
    ) {
        TapRender.render(
            input: UnsafePointer(input.list.unsafeMutablePointer),
            output: output.list.unsafeMutablePointer,
            plan: plan,
            targetGain: targetGain,
            currentGain: &gain,
            rampCoefficient: coefficient
        )
    }

    private func writeFrame(
        left: Float,
        right: Float,
        channels: Int,
        offset: Int,
        total: Int,
        gain: Float
    ) -> [Float] {
        var output = [Float](repeating: .nan, count: channels)
        output.withUnsafeMutableBufferPointer { buffer in
            TapRender.writeFrame(
                left: left,
                right: right,
                into: buffer.baseAddress!,
                channels: channels,
                globalChannelOffset: offset,
                totalOutputChannels: total,
                gain: gain
            )
        }
        return output
    }

    func testWriteFrameStereo() {
        XCTAssertEqual(writeFrame(left: 0.5, right: -0.25, channels: 2, offset: 0, total: 2, gain: 1), [0.5, -0.25])
    }

    func testWriteFrameMonoOutputIsMixdown() {
        XCTAssertEqual(writeFrame(left: 0.5, right: 0.25, channels: 1, offset: 0, total: 1, gain: 1), [0.375])
    }

    func testWriteFrameExtraChannelsAreZero() {
        XCTAssertEqual(writeFrame(left: 0.5, right: 0.25, channels: 4, offset: 0, total: 4, gain: 1), [0.5, 0.25, 0, 0])
    }

    func testWriteFrameGlobalOffset() {
        XCTAssertEqual(writeFrame(left: 0.5, right: 0.25, channels: 2, offset: 2, total: 4, gain: 1), [0, 0])
    }

    func testClampAtUnity() {
        XCTAssertEqual(writeFrame(left: 0.8, right: -0.9, channels: 2, offset: 0, total: 2, gain: 2), [1, -1])
    }

    func testRenderStereoInterleaved() {
        let input = TestBufferList(channels: [2], frames: 2)
        let output = TestBufferList(channels: [2], frames: 2)
        input.write([0.5, -0.5, 0.25, 0], at: 0)
        var gain: Float = 0

        render(
            input: input,
            output: output,
            plan: TapRenderPlan(tapInputIndex: 0, tapInputChannels: 2),
            targetGain: 1,
            coefficient: 1,
            gain: &gain
        )

        XCTAssertEqual(output.read(at: 0), [0.5, -0.5, 0.25, 0])
        XCTAssertEqual(gain, 1, accuracy: 0.0001)
    }

    func testRenderPlanarOutputUsesOneRamp() {
        let input = TestBufferList(channels: [2], frames: 2)
        let output = TestBufferList(channels: [1, 1], frames: 2)
        input.write([0.25, 0.5, 0.25, 0.5], at: 0)
        var gain: Float = 0

        render(
            input: input,
            output: output,
            plan: TapRenderPlan(tapInputIndex: 0, tapInputChannels: 2),
            targetGain: 2,
            coefficient: 0.5,
            gain: &gain
        )

        let left = output.read(at: 0)
        let right = output.read(at: 1)
        XCTAssertEqual(left[0], 0.25, accuracy: 0.0001)
        XCTAssertEqual(right[0], 0.5, accuracy: 0.0001)
        XCTAssertEqual(left[1], 0.375, accuracy: 0.0001)
        XCTAssertEqual(right[1], 0.75, accuracy: 0.0001)
        XCTAssertEqual(right[0] / left[0], 2, accuracy: 0.0001)
        XCTAssertEqual(gain, 1.5, accuracy: 0.0001)
    }

    func testRenderMuteWritesSilence() {
        let input = TestBufferList(channels: [2], frames: 2)
        let output = TestBufferList(channels: [2], frames: 2)
        input.write([1, 1, 1, 1], at: 0)
        var gain: Float = 1

        render(
            input: input,
            output: output,
            plan: TapRenderPlan(tapInputIndex: 0, tapInputChannels: 2),
            targetGain: 0,
            coefficient: 1,
            gain: &gain
        )

        XCTAssertEqual(output.read(at: 0), [0, 0, 0, 0])
        XCTAssertEqual(gain, 0, accuracy: 0.0001)
    }

    func testRenderMonoTapDuplicatesToStereo() {
        let input = TestBufferList(channels: [1], frames: 2)
        let output = TestBufferList(channels: [2], frames: 2)
        input.write([0.4, -0.2], at: 0)
        var gain: Float = 0

        render(
            input: input,
            output: output,
            plan: TapRenderPlan(tapInputIndex: 0, tapInputChannels: 1),
            targetGain: 1,
            coefficient: 1,
            gain: &gain
        )

        XCTAssertEqual(output.read(at: 0), [0.4, 0.4, -0.2, -0.2])
    }

    func testRenderUsesLastInputBuffer() {
        let output = TestBufferList(channels: [2], frames: 1)
        let input = TestBufferList(channels: [2, 2], frames: 1)
        var gain: Float = 0
        input.write([9, 9], at: 0)
        input.write([0.5, -0.5], at: 1)

        render(
            input: input,
            output: output,
            plan: TapRenderPlan(tapInputIndex: 1, tapInputChannels: 2),
            targetGain: 1,
            coefficient: 1,
            gain: &gain
        )

        XCTAssertEqual(output.read(at: 0), [0.5, -0.5])
    }
}
