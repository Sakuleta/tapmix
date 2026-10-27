import Foundation

/// Magnitude response of the ten bands plus imported AutoEQ filters, sampled on
/// a log frequency axis for the EQ curve in the panel.
public enum EQResponse {
    public static func points(
        for settings: EQSettings,
        sampleRate: Double = 48_000,
        count: Int = 120
    ) -> [Float] {
        guard count > 1 else { return [] }
        let coefficients = coefficients(for: settings, sampleRate: sampleRate)
        guard !coefficients.isEmpty else { return Array(repeating: 0, count: count) }

        let minFrequency: Float = 20
        let maxFrequency: Float = 20_000
        return (0 ..< count).map { index in
            let t = Float(index) / Float(count - 1)
            let frequency = minFrequency * pow(maxFrequency / minFrequency, t)
            return decibels(at: frequency, coefficients: coefficients, sampleRate: sampleRate)
        }
    }

    public static func decibels(
        at frequency: Float,
        settings: EQSettings,
        sampleRate: Double = 48_000
    ) -> Float {
        decibels(
            at: frequency,
            coefficients: coefficients(for: settings, sampleRate: sampleRate),
            sampleRate: sampleRate
        )
    }

    static func coefficients(
        for settings: EQSettings,
        sampleRate: Double
    ) -> [BiquadCoefficient] {
        var coefficients: [BiquadCoefficient] = []

        if settings.enabled {
            for band in 0 ..< EQSettings.bandCount {
                coefficients.append(
                    EQProcessor.peaking(
                        frequency: EQSettings.frequencies[band],
                        gainDB: settings.gains[band],
                        sampleRate: sampleRate
                    )
                )
            }
        }

        for filter in settings.filters.prefix(EQFilterParser.maxFilters) {
            coefficients.append(EQProcessor.coefficient(for: filter, sampleRate: sampleRate))
        }

        return coefficients
    }

    private static func decibels(
        at frequency: Float,
        coefficients: [BiquadCoefficient],
        sampleRate: Double
    ) -> Float {
        guard frequency > 0, sampleRate > 0 else { return 0 }
        let omega = Double(2 * Float.pi * frequency / Float(sampleRate))
        let zr = cos(omega)
        let zi = -sin(omega)
        let z2r = zr * zr - zi * zi
        let z2i = 2 * zr * zi

        var total = 1.0
        for coefficient in coefficients {
            let b0 = Double(coefficient.b0)
            let b1 = Double(coefficient.b1)
            let b2 = Double(coefficient.b2)
            let a1 = Double(coefficient.a1)
            let a2 = Double(coefficient.a2)

            let numeratorReal = b0 + b1 * zr + b2 * z2r
            let numeratorImaginary = b1 * zi + b2 * z2i
            let denominatorReal = 1 + a1 * zr + a2 * z2r
            let denominatorImaginary = a1 * zi + a2 * z2i

            let numerator = sqrt(numeratorReal * numeratorReal + numeratorImaginary * numeratorImaginary)
            let denominator = max(
                sqrt(denominatorReal * denominatorReal + denominatorImaginary * denominatorImaginary),
                1e-12
            )
            total *= numerator / denominator
        }

        return Float(20 * log10(max(total, 1e-9)))
    }
}
