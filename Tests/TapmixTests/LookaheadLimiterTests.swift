import XCTest
@testable import TapmixCore

final class LookaheadLimiterTests: XCTestCase {
    private func makeLimiter() -> LookaheadLimiter {
        LookaheadLimiter(sampleRate: 1000, lookaheadSeconds: 0.005, releaseSeconds: 0.1)
    }

    func testLookaheadDelaysOutput() {
        let limiter = makeLimiter()
        let first = limiter.process(left: 0.5, right: 0.5)
        XCTAssertEqual(first.left, 0)
        XCTAssertEqual(first.right, 0)
    }

    func testQuietSignalPassesUnchanged() {
        let limiter = makeLimiter()
        var left: Float = 0
        var right: Float = 0
        for _ in 0..<100 {
            let output = limiter.process(left: 0.5, right: -0.5)
            left = output.left
            right = output.right
        }
        XCTAssertEqual(left, 0.5, accuracy: 0.0001)
        XCTAssertEqual(right, -0.5, accuracy: 0.0001)
    }

    func testLoudPeakIsLimited() {
        let limiter = makeLimiter()
        var peak: Float = 0
        for _ in 0..<100 {
            let output = limiter.process(left: 4, right: -4)
            peak = max(peak, abs(output.left), abs(output.right))
        }
        XCTAssertLessThanOrEqual(peak, LookaheadLimiter.ceiling + 0.0001)
    }

    func testStereoIsLinked() {
        let limiter = makeLimiter()
        var output = (left: Float(0), right: Float(0))
        for _ in 0..<100 {
            output = limiter.process(left: 4, right: 1)
        }
        XCTAssertEqual(output.left, LookaheadLimiter.ceiling, accuracy: 0.0001)
        XCTAssertEqual(output.right / output.left, 0.25, accuracy: 0.0001)
    }

    func testReleaseRecoversAfterPeak() {
        let limiter = makeLimiter()
        for _ in 0..<20 {
            _ = limiter.process(left: 4, right: 4)
        }
        var output: Float = 0
        for _ in 0..<1000 {
            output = limiter.process(left: 0.5, right: 0.5).left
        }
        XCTAssertEqual(output, 0.5, accuracy: 0.02)
    }
}
