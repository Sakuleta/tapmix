import XCTest
@testable import TapmixCore

final class AudioMathTests: XCTestCase {
    func testStereoCopyAtUnityGain() {
        let input: [Float] = [0.5, -0.5, 0.25, 0]
        var output = [Float](repeating: 9, count: 4)
        var gain: Float = 0

        input.withUnsafeBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                AudioMath.process(
                    input: inputBuffer.baseAddress!,
                    inputChannels: 2,
                    inputFrames: 2,
                    output: outputBuffer.baseAddress!,
                    outputChannels: 2,
                    outputFrames: 2,
                    targetGain: 1,
                    currentGain: &gain,
                    rampCoefficient: 1
                )
            }
        }

        XCTAssertEqual(output, [0.5, -0.5, 0.25, 0])
        XCTAssertEqual(gain, 1, accuracy: 0.0001)
    }

    func testMonoIsDuplicatedToStereo() {
        let input: [Float] = [0.4, -0.2]
        var output = [Float](repeating: 0, count: 4)
        var gain: Float = 0

        input.withUnsafeBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                AudioMath.process(
                    input: inputBuffer.baseAddress!,
                    inputChannels: 1,
                    inputFrames: 2,
                    output: outputBuffer.baseAddress!,
                    outputChannels: 2,
                    outputFrames: 2,
                    targetGain: 1,
                    currentGain: &gain,
                    rampCoefficient: 1
                )
            }
        }

        XCTAssertEqual(output, [0.4, 0.4, -0.2, -0.2])
    }

    func testBoostClampsAndFillsTailWithSilence() {
        let input: [Float] = [0.8, -0.9]
        var output = [Float](repeating: 7, count: 6)
        var gain: Float = 0

        input.withUnsafeBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                AudioMath.process(
                    input: inputBuffer.baseAddress!,
                    inputChannels: 2,
                    inputFrames: 1,
                    output: outputBuffer.baseAddress!,
                    outputChannels: 2,
                    outputFrames: 3,
                    targetGain: 2,
                    currentGain: &gain,
                    rampCoefficient: 1
                )
            }
        }

        XCTAssertEqual(output, [1, -1, 0, 0, 0, 0])
        XCTAssertEqual(gain, 2, accuracy: 0.0001)
    }

    func testMutedGainRampsToSilence() {
        let input: [Float] = [1, 1, 1, 1]
        var output = [Float](repeating: 0, count: 4)
        var gain: Float = 1

        input.withUnsafeBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                AudioMath.process(
                    input: inputBuffer.baseAddress!,
                    inputChannels: 2,
                    inputFrames: 2,
                    output: outputBuffer.baseAddress!,
                    outputChannels: 2,
                    outputFrames: 2,
                    targetGain: 0,
                    currentGain: &gain,
                    rampCoefficient: 1
                )
            }
        }

        XCTAssertEqual(output, [0, 0, 0, 0])
        XCTAssertEqual(gain, 0, accuracy: 0.0001)
    }

    func testLevelStoreRoundTrip() {
        let suiteName = "com.sakuleta.tapmix.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LevelStore(defaults: defaults)
        XCTAssertEqual(store.level(for: "com.example.app").volume, 1)
        XCTAssertFalse(store.level(for: "com.example.app").muted)

        store.set(AppLevel(volume: 1.4, muted: true), for: "com.example.app")

        let reloaded = LevelStore(defaults: defaults)
        XCTAssertEqual(reloaded.level(for: "com.example.app").volume, 1.4, accuracy: 0.0001)
        XCTAssertTrue(reloaded.level(for: "com.example.app").muted)
        XCTAssertEqual(reloaded.level(for: "com.example.app").gain, 0)
    }
}
