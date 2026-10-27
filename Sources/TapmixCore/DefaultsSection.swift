import Foundation

/// One `Codable` value stored as JSON under a defaults key.
///
/// The four app-state stores keep their own small interfaces and their existing
/// keys; only the duplicated read/encode/decode plumbing lives here.
struct DefaultsSection<Value: Codable> {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String) {
        self.defaults = defaults
        self.key = key
    }

    func load(default fallback: Value) -> Value {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Value.self, from: data)
        else { return fallback }
        return decoded
    }

    func save(_ value: Value) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
