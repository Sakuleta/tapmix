import Carbon
import Foundation
import TapmixCore

enum HotKeyModifiers: String, CaseIterable, Identifiable {
    case optionCommand
    case controlOption
    case commandShift
    case off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .optionCommand: return "⌥⌘ (default)"
        case .controlOption: return "⌃⌥"
        case .commandShift: return "⇧⌘"
        case .off: return "Off"
        }
    }

    var carbonFlags: UInt32? {
        switch self {
        case .optionCommand: return UInt32(optionKey | cmdKey)
        case .controlOption: return UInt32(controlKey | optionKey)
        case .commandShift: return UInt32(shiftKey | cmdKey)
        case .off: return nil
        }
    }
}

@MainActor
final class HotKeyController: ObservableObject {
    static let shared = HotKeyController()

    @Published private(set) var modifiers: HotKeyModifiers
    private var center: HotKeyCenter?
    private static let key = "com.mardinli.tapmix.hotkeyModifiers"

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.key)
        modifiers = raw.flatMap(HotKeyModifiers.init(rawValue:)) ?? .optionCommand
    }

    func start() {
        register()
    }

    func setModifiers(_ value: HotKeyModifiers) {
        modifiers = value
        UserDefaults.standard.set(value.rawValue, forKey: Self.key)
        register()
    }

    private func register() {
        center = nil
        guard let flags = modifiers.carbonFlags else { return }

        let center = HotKeyCenter()
        center.register(keyCode: UInt32(kVK_UpArrow), modifiers: flags, id: 1) {
            guard let state = AudioEngine.shared.stepActiveVolume(by: 0.05) else { return }
            HUDController.shared.show(name: state.name, volume: state.volume, muted: state.muted)
        }
        center.register(keyCode: UInt32(kVK_DownArrow), modifiers: flags, id: 2) {
            guard let state = AudioEngine.shared.stepActiveVolume(by: -0.05) else { return }
            HUDController.shared.show(name: state.name, volume: state.volume, muted: state.muted)
        }
        center.register(keyCode: UInt32(kVK_ANSI_M), modifiers: flags, id: 3) {
            guard let state = AudioEngine.shared.toggleActiveMute() else { return }
            HUDController.shared.show(name: state.name, volume: state.volume, muted: state.muted)
        }
        self.center = center
    }
}
