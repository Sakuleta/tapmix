import Foundation
import Synchronization

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

/// Ten peaking bands plus imported AutoEQ filters per channel.
///
/// Coefficients live in three banks. The writer fills the bank after the
/// published one and releases it; the renderer loads the published bank with an
/// acquire and reads it in place, so the callback never copies or allocates.
/// Three banks keep a bank being written away from the two the renderer can
/// still be holding after two updates in one callback.
final class EQProcessor {
    private static let bankCount = 3

    private let fixedCount = EQSettings.bandCount
    private let capacity = EQSettings.bandCount + EQFilterParser.maxFilters
    private let sampleRate: Double
    private let banks: UnsafeMutablePointer<BiquadCoefficient>
    private let published = Atomic<Int>(0)
    private let leftStates: UnsafeMutablePointer<BiquadState>
    private let rightStates: UnsafeMutablePointer<BiquadState>
    private var enabled = false
    private var activeCount = 0

    init(sampleRate: Double) {
        self.sampleRate = max(sampleRate, 8000)

        let slots = Self.bankCount * capacity
        banks = UnsafeMutablePointer<BiquadCoefficient>.allocate(capacity: slots)
        banks.initialize(repeating: BiquadCoefficient(), count: slots)
        leftStates = UnsafeMutablePointer<BiquadState>.allocate(capacity: capacity)
        leftStates.initialize(repeating: BiquadState(), count: capacity)
        rightStates = UnsafeMutablePointer<BiquadState>.allocate(capacity: capacity)
        rightStates.initialize(repeating: BiquadState(), count: capacity)
    }

    deinit {
        banks.deinitialize(count: Self.bankCount * capacity)
        banks.deallocate()
        leftStates.deinitialize(count: capacity)
        leftStates.deallocate()
        rightStates.deinitialize(count: capacity)
        rightStates.deallocate()
    }

    func update(_ settings: EQSettings) {
        let bank = (published.load(ordering: .relaxed) + 1) % Self.bankCount
        let base = bank * capacity
        var index = 0

        for band in 0 ..< fixedCount {
            if settings.enabled {
                banks[base + index] = Self.peaking(
                    frequency: EQSettings.frequencies[band],
                    gainDB: settings.gains[band],
                    sampleRate: sampleRate
                )
            } else {
                banks[base + index] = BiquadCoefficient()
            }
            index += 1
        }

        for filter in settings.filters.prefix(EQFilterParser.maxFilters) {
            banks[base + index] = Self.coefficient(for: filter, sampleRate: sampleRate)
            index += 1
        }
        activeCount = index
        enabled = settings.enabled || !settings.filters.isEmpty

        while index < capacity {
            banks[base + index] = BiquadCoefficient()
            index += 1
        }

        published.store(bank, ordering: .releasing)
    }

    @inline(__always)
    func process(left: Float, right: Float) -> (left: Float, right: Float) {
        let base = published.load(ordering: .acquiring) * capacity
        guard enabled else { return (left, right) }

        var leftSample = left
        var rightSample = right
        for index in 0 ..< activeCount {
            let coefficient = banks[base + index]
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

    static func coefficient(for filter: EQFilter, sampleRate: Double) -> BiquadCoefficient {
        switch filter.kind {
        case .peaking:
            return peaking(
                frequency: filter.frequency,
                gainDB: filter.gainDB,
                sampleRate: sampleRate,
                q: max(filter.q, 0.1)
            )
        case .lowShelf:
            return shelf(
                frequency: filter.frequency,
                gainDB: filter.gainDB,
                sampleRate: sampleRate,
                high: false
            )
        case .highShelf:
            return shelf(
                frequency: filter.frequency,
                gainDB: filter.gainDB,
                sampleRate: sampleRate,
                high: true
            )
        }
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
        return BiquadCoefficient(
            b0: (1 + alpha * a) / a0,
            b1: b1,
            b2: (1 - alpha * a) / a0,
            a1: b1,
            a2: (1 - alpha / a) / a0
        )
    }

    /// RBJ low/high shelf with S = 1. AutoEQ's shelf Q is not used.
    static func shelf(
        frequency: Float,
        gainDB: Float,
        sampleRate: Double,
        high: Bool
    ) -> BiquadCoefficient {
        let nyquist = Float(sampleRate) * 0.5
        guard abs(gainDB) > 0.01, frequency > 0, frequency < nyquist * 0.98 else {
            return BiquadCoefficient()
        }

        let a = pow(10, gainDB / 40)
        let omega = 2 * Float.pi * frequency / Float(sampleRate)
        let cosw = cos(omega)
        let alpha = sin(omega) / 2 * sqrt(2)
        let beta = 2 * sqrt(a) * alpha
        let a0: Float
        let b0: Float
        let b1: Float
        let b2: Float
        let a1: Float
        let a2: Float

        if high {
            b0 = a * ((a + 1) + (a - 1) * cosw + beta)
            b1 = -2 * a * ((a - 1) + (a + 1) * cosw)
            b2 = a * ((a + 1) + (a - 1) * cosw - beta)
            a0 = (a + 1) - (a - 1) * cosw + beta
            a1 = 2 * ((a - 1) - (a + 1) * cosw)
            a2 = (a + 1) - (a - 1) * cosw - beta
        } else {
            b0 = a * ((a + 1) - (a - 1) * cosw + beta)
            b1 = 2 * a * ((a - 1) - (a + 1) * cosw)
            b2 = a * ((a + 1) - (a - 1) * cosw - beta)
            a0 = (a + 1) + (a - 1) * cosw + beta
            a1 = -2 * ((a - 1) + (a + 1) * cosw)
            a2 = (a + 1) + (a - 1) * cosw - beta
        }

        return BiquadCoefficient(
            b0: b0 / a0,
            b1: b1 / a0,
            b2: b2 / a0,
            a1: a1 / a0,
            a2: a2 / a0
        )
    }
}
