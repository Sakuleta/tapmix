import Foundation

public struct EQFilter: Codable, Equatable {
    public enum Kind: String, Codable {
        case peaking = "PK"
        case lowShelf = "LSC"
        case highShelf = "HSC"
    }

    public var kind: Kind
    public var frequency: Float
    public var gainDB: Float
    public var q: Float

    public init(kind: Kind, frequency: Float, gainDB: Float, q: Float) {
        self.kind = kind
        self.frequency = frequency
        self.gainDB = gainDB
        self.q = q
    }
}

/// Parses the `ParametricEQ.txt` format used by AutoEQ and Equalizer APO.
public enum EQFilterParser {
    public static let maxFilters = 24

    public static func parse(_ text: String) -> [EQFilter] {
        var filters: [EQFilter] = []

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("filter") else { continue }
            guard let kind = kind(in: trimmed), let frequency = number(after: "Fc", in: trimmed),
                  let gain = number(after: "Gain", in: trimmed)
            else { continue }

            let q = number(after: "Q", in: trimmed) ?? 0.707
            filters.append(EQFilter(kind: kind, frequency: frequency, gainDB: gain, q: max(q, 0.1)))
            if filters.count == maxFilters { break }
        }

        return filters
    }

    private static func kind(in line: String) -> EQFilter.Kind? {
        let tokens = line.split(whereSeparator: \.isWhitespace).map { $0.uppercased() }
        guard let token = tokens.first(where: { ["PK", "LSC", "HSC", "LS", "HS"].contains($0) }) else {
            return nil
        }
        switch token {
        case "PK": return .peaking
        case "LSC", "LS": return .lowShelf
        case "HSC", "HS": return .highShelf
        default: return nil
        }
    }

    private static func number(after key: String, in line: String) -> Float? {
        let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let index = tokens.firstIndex(where: { $0.caseInsensitiveCompare(key) == .orderedSame }),
              index + 1 < tokens.count
        else { return nil }
        return Float(tokens[index + 1].replacingOccurrences(of: ",", with: "."))
    }
}
