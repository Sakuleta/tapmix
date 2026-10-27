import XCTest
@testable import TapmixCore

final class EQProcessorTests: XCTestCase {
    private func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return sqrt(sum / Float(samples.count))
    }

    func testDisabledPassesThrough() {
        let processor = EQProcessor(sampleRate: 48_000)
        processor.update(EQSettings(enabled: false, gains: [12, 12, 12, 12, 12, 12, 12, 12, 12, 12]))

        let output = processor.process(left: 0.7, right: -0.4)
        XCTAssertEqual(output.left, 0.7, accuracy: 0.0001)
        XCTAssertEqual(output.right, -0.4, accuracy: 0.0001)
    }

    func testFlatEnabledPassesThrough() {
        let processor = EQProcessor(sampleRate: 48_000)
        processor.update(EQSettings(enabled: true))

        let output = processor.process(left: 0.25, right: -0.75)
        XCTAssertEqual(output.left, 0.25, accuracy: 0.0001)
        XCTAssertEqual(output.right, -0.75, accuracy: 0.0001)
    }

    func testPeakingBoostsCenterFrequency() {
        let processor = EQProcessor(sampleRate: 48_000)
        var gains = [Float](repeating: 0, count: EQSettings.bandCount)
        gains[5] = 6
        processor.update(EQSettings(enabled: true, gains: gains))

        let sampleRate: Float = 48_000
        var input: [Float] = []
        var output: [Float] = []
        for index in 0 ..< 96_000 {
            let value = sin(2 * Float.pi * 1000 * Float(index) / sampleRate) * 0.5
            if index >= 9_600 {
                input.append(value)
                output.append(processor.process(left: value, right: value).left)
            } else {
                _ = processor.process(left: value, right: value)
            }
        }

        let ratio = rms(output) / rms(input)
        let expected = Float(pow(10.0, 6.0 / 20.0))
        XCTAssertEqual(ratio, expected, accuracy: 0.1)
    }

    func testBandAboveNyquistIsBypassed() {
        let coefficient = EQProcessor.peaking(frequency: 16_000, gainDB: 12, sampleRate: 16_000)
        XCTAssertEqual(coefficient.b0, 1, accuracy: 0.0001)
        XCTAssertEqual(coefficient.b1, 0, accuracy: 0.0001)
        XCTAssertEqual(coefficient.b2, 0, accuracy: 0.0001)
        XCTAssertEqual(coefficient.a1, 0, accuracy: 0.0001)
        XCTAssertEqual(coefficient.a2, 0, accuracy: 0.0001)
    }

    func testImportedFilterAppliesWhileBandsAreOff() {
        let processor = EQProcessor(sampleRate: 48_000)
        processor.update(EQSettings(
            enabled: false,
            filters: [EQFilter(kind: .peaking, frequency: 1_000, gainDB: 6, q: 1.4)]
        ))

        let sampleRate: Float = 48_000
        var input: [Float] = []
        var output: [Float] = []
        for index in 0 ..< 96_000 {
            let value = sin(2 * Float.pi * 1000 * Float(index) / sampleRate) * 0.5
            let processed = processor.process(left: value, right: value).left
            if index >= 9_600 {
                input.append(value)
                output.append(processed)
            }
        }

        let ratio = rms(output) / rms(input)
        XCTAssertEqual(ratio, Float(pow(10.0, 6.0 / 20.0)), accuracy: 0.1)
    }

    func testLowShelfBoostsLowFrequencies() {
        let processor = EQProcessor(sampleRate: 48_000)
        processor.update(EQSettings(
            enabled: false,
            filters: [EQFilter(kind: .lowShelf, frequency: 100, gainDB: 6, q: 0.7)]
        ))

        var output: Float = 0
        for _ in 0 ..< 96_000 {
            output = processor.process(left: 0.25, right: 0.25).left
        }
        XCTAssertEqual(output, 0.25 * Float(pow(10.0, 6.0 / 20.0)), accuracy: 0.01)
    }

    func testCoefficientsStayFinite() {
        for band in EQSettings.frequencies {
            for gain: Float in [-12, -6, 0, 6, 12] {
                let coefficient = EQProcessor.peaking(frequency: band, gainDB: gain, sampleRate: 48_000)
                XCTAssertTrue(coefficient.b0.isFinite)
                XCTAssertTrue(coefficient.b1.isFinite)
                XCTAssertTrue(coefficient.b2.isFinite)
                XCTAssertTrue(coefficient.a1.isFinite)
                XCTAssertTrue(coefficient.a2.isFinite)
            }
        }
    }
}
