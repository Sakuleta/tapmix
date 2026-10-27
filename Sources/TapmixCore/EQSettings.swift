import Foundation

public struct EQSettings: Codable, Equatable {
    public static let bandCount = 10
    public static let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    public static let gainRange: ClosedRange<Float> = -12 ... 12

    public var enabled: Bool
    public var gains: [Float]
    /// Imported AutoEQ / parametric correction filters.
    public var filters: [EQFilter]

    public init(enabled: Bool = false, gains: [Float] = [], filters: [EQFilter] = []) {
        self.enabled = enabled
        self.gains = Self.normalized(gains)
        self.filters = Array(filters.prefix(EQFilterParser.maxFilters))
    }

    public var isFlat: Bool {
        gains.allSatisfy { abs($0) < 0.01 }
    }

    public var isActive: Bool {
        (enabled && !isFlat) || !filters.isEmpty
    }

    static func normalized(_ gains: [Float]) -> [Float] {
        (0 ..< bandCount).map { index in
            guard index < gains.count else { return 0 }
            return min(max(gains[index], gainRange.lowerBound), gainRange.upperBound)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, gains, filters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        gains = Self.normalized(try container.decodeIfPresent([Float].self, forKey: .gains) ?? [])
        filters = try container.decodeIfPresent([EQFilter].self, forKey: .filters) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(gains, forKey: .gains)
        try container.encode(filters, forKey: .filters)
    }
}

public enum EQPreset: String, CaseIterable, Identifiable {
    case flat = "Flat"
    case bass = "Bass Boost"
    case vocal = "Vocal Clarity"
    case treble = "Treble"
    case loudness = "Loudness"

    public var id: String { rawValue }

    public var settings: EQSettings {
        switch self {
        case .flat:
            return EQSettings()
        case .bass:
            return EQSettings(enabled: true, gains: [7, 6, 4, 2, 0, 0, 0, 0, 0, 0])
        case .vocal:
            return EQSettings(enabled: true, gains: [-3, -2, 0, 2, 4, 4, 3, 1, 0, -1])
        case .treble:
            return EQSettings(enabled: true, gains: [0, 0, 0, 0, 0, 1, 2, 4, 6, 7])
        case .loudness:
            return EQSettings(enabled: true, gains: [6, 5, 2, 0, -1, -1, 0, 1, 3, 5])
        }
    }
}
