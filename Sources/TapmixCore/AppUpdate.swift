import Foundation

public enum AppUpdate {
    /// Compares dotted numeric versions; a leading `v` and suffixes are ignored.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = components(candidate)
        let right = components(current)
        let count = max(left.count, right.count)

        for index in 0 ..< count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    static func components(_ version: String) -> [Int] {
        var trimmed = version.trimmingCharacters(in: .whitespaces)
        if trimmed.first == "v" || trimmed.first == "V" {
            trimmed.removeFirst()
        }

        var numeric = ""
        for character in trimmed {
            if character.isNumber || character == "." {
                numeric.append(character)
            } else {
                break
            }
        }

        return numeric.split(separator: ".").map { Int($0) ?? 0 }
    }
}
