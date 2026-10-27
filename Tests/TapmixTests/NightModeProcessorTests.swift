import XCTest
@testable import TapmixCore

final class NightModeProcessorTests: XCTestCase {
    private func process(
        _ processor: NightModeProcessor,
        left: Float,
        right: Float? = nil,
        frames: Int
    ) -> (left: Float, right: Float) {
        var output = (left: Float(0), right: Float(0))
        for _ in 0 ..< frames {
            output = processor.process(left: left, right: right ?? left)
        }
        return output
    }

    func testDisabledPassesThrough() {
        let processor = NightModeProcessor(sampleRate: 48_000)
        let output = process(processor, left: 0.7, right: -0.4, frames: 100)
        XCTAssertEqual(output.left, 0.7, accuracy: 0.0001)
        XCTAssertEqual(output.right, -0.4, accuracy: 0.0001)
    }

    func testQuietSignalIsLifted() {
        let processor = NightModeProcessor(sampleRate: 48_000)
        processor.setEnabled(true)
        let output = process(processor, left: 0.05, frames: 48_000)
        XCTAssertEqual(output.left, 0.05 * NightModeProcessor.makeup, accuracy: 0.005)
    }

    func testLoudSignalIsCompressed() {
        let processor = NightModeProcessor(sampleRate: 48_000)
        processor.setEnabled(true)
        let output = process(processor, left: 0.8, frames: 48_000)
        XCTAssertLessThan(output.left, 0.6)
        XCTAssertGreaterThan(output.left, 0.3)
    }

    func testStereoIsLinked() {
        let processor = NightModeProcessor(sampleRate: 48_000)
        processor.setEnabled(true)
        let output = process(processor, left: 0.8, right: 0.4, frames: 48_000)
        XCTAssertEqual(output.left / output.right, 2, accuracy: 0.001)
    }

    func testSilenceStaysSilentAndFinite() {
        let processor = NightModeProcessor(sampleRate: 48_000)
        processor.setEnabled(true)
        let output = process(processor, left: 0, frames: 1_000)
        XCTAssertEqual(output.left, 0, accuracy: 0.0001)
        XCTAssertTrue(output.left.isFinite)
    }

    func testDisableAndReenableResetsGain() {
        let processor = NightModeProcessor(sampleRate: 48_000)
        processor.setEnabled(true)
        _ = process(processor, left: 0.8, frames: 4_800)
        processor.setEnabled(false)
        processor.setEnabled(true)

        let first = processor.process(left: 0.8, right: 0.8).left
        XCTAssertEqual(first, 0.8, accuracy: 0.05)
    }
}
