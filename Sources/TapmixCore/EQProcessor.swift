import Foundation

struct BiquadCoefficient {
    var b0: Float = 1
    var b1: Float = 0
    var b2: Float = 0
    var a1: Float = 0
    var a2: Float = 0
}

struct BiquadState {
    var x1: Float = 0
    var x2: Float = 0
    var y1: Float = 0
    var y2: Float = 0
}

/// Ten peaking filters per channel. Coefficients are computed on the main
/// thread and copied into the realtime renderer when the revision changes;
/// `process` does no allocation, locking or logging.
final class EQProcessor {
    private let bandCount = EQSettings.bandCount
    private let sampleRate: Double
    private let coefficients: UnsafeMutablePointer<BiquadCoefficient>
    private let active: UnsafeMutablePointer<BiquadCoefficient>
    private let leftStates: UnsafeMutablePointer<BiquadState>
    private let rightStates: UnsafeMutablePointer<BiquadState>
    private var enabled = false
    private var pendingEnabled = false
    private var revision: Int32 = 0
    private var appliedRevision: Int32 = -1

    init(sampleRate: Double) {
        self.sampleRate = max(sampleRate, 8000)

        coefficients = UnsafeMutablePointer<BiquadCoefficient>.allocate(capacity: bandCount)
        coefficients.initialize(repeating: BiquadCoefficient(), count: bandCount)
        active = UnsafeMutablePointer<BiquadCoefficient>.allocate(capacity: bandCount)
        active.initialize(repeating: BiquadCoefficient(), count: bandCount)
        leftStates = UnsafeMutablePointer<BiquadState>.allocate(capacity: bandCount)
        leftStates.initialize(repeating: BiquadState(), count: bandCount)
        rightStates = UnsafeMutablePointer<BiquadState>.allocate(capacity: bandCount)
        rightStates.initialize(repeating: BiquadState(), count: bandCount)
    }

    deinit {
        coefficients.deinitialize(count: bandCount)
        coefficients.deallocate()
        active.deinitialize(count: bandCount)
        active.deallocate()
        leftStates.deinitialize(count: bandCount)
        leftStates.deallocate()
        rightStates.deinitialize(count: bandCount)
        rightStates.deallocate()
    }

    func update(_ settings: EQSettings) {
        for index in 0 ..< bandCount {
            coefficients[index] = Self.peaking(
                frequency: EQSettings.frequencies[index],
                gainDB: settings.gains[index],
                sampleRate: sampleRate
            )
        }
        pendingEnabled = settings.enabled
        revision &+= 1
    }

    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        if revision != appliedRevision {
            appliedRevision = revision
            enabled = pendingEnabled
            for index in 0 ..< bandCount {
                active[index] = coefficients[index]
            }
        }
        guard enabled else { return (left, right) }

        var leftSample = left
        var rightSample = right
        for index in 0 ..< bandCount {
            let coefficient = active[index]
            leftSample = Self.filter(leftSample, state: &leftStates[index], coefficient: coefficient)
            rightSample = Self.filter(rightSample, state: &rightStates[index], coefficient: coefficient)
        }
        return (leftSample, rightSample)
    }

    @inline(__always)
    private static func filter(
        _ sample: Float,
        state: inout BiquadState,
        coefficient: BiquadCoefficient
    ) -> Float {
        let output = coefficient.b0 * sample
            + coefficient.b1 * state.x1
            + coefficient.b2 * state.x2
            - coefficient.a1 * state.y1
            - coefficient.a2 * state.y2
        state.x2 = state.x1
        state.x1 = sample
        state.y2 = state.y1
        state.y1 = output
        return output
    }

    static func peaking(
        frequency: Float,
        gainDB: Float,
        sampleRate: Double,
        q: Float = 1.4
    ) -> BiquadCoefficient {
        let nyquist = Float(sampleRate) * 0.5
        guard abs(gainDB) > 0.01, frequency > 0, frequency < nyquist * 0.98 else {
            return BiquadCoefficient()
        }

        let a = pow(10, gainDB / 40)
        let omega = 2 * Float.pi * frequency / Float(sampleRate)
        let alpha = sin(omega) / (2 * q)
        let a0 = 1 + alpha / a
        let b1 = -2 * cos(omega) / a0
        let a1 = b1
        return BiquadCoefficient(
            b0: (1 + alpha * a) / a0,
            b1: b1,
            b2: (1 - alpha * a) / a0,
            a1: a1,
            a2: (1 - alpha / a) / a0
        )
    }
}
