import AppKit
import Carbon
import TapmixCore
import SwiftUI

@main
struct TapmixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var engine = AudioEngine.shared

    var body: some Scene {
        MenuBarExtra {
            PanelView(engine: engine)
        } label: {
            Image(systemName: engine.outputMuted ? "speaker.slash" : "waveform")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKeys: HotKeyCenter?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AudioEngine.shared.start()

        let hotKeys = HotKeyCenter()
        let modifiers = UInt32(cmdKey | optionKey)

        hotKeys.register(keyCode: UInt32(kVK_UpArrow), modifiers: modifiers, id: 1) {
            guard let state = AudioEngine.shared.stepActiveVolume(by: 0.05) else { return }
            HUDController.shared.show(name: state.name, volume: state.volume, muted: state.muted)
        }
        hotKeys.register(keyCode: UInt32(kVK_DownArrow), modifiers: modifiers, id: 2) {
            guard let state = AudioEngine.shared.stepActiveVolume(by: -0.05) else { return }
            HUDController.shared.show(name: state.name, volume: state.volume, muted: state.muted)
        }
        hotKeys.register(keyCode: UInt32(kVK_ANSI_M), modifiers: modifiers, id: 3) {
            guard let state = AudioEngine.shared.toggleActiveMute() else { return }
            HUDController.shared.show(name: state.name, volume: state.volume, muted: state.muted)
        }
        self.hotKeys = hotKeys
    }

    func applicationWillTerminate(_ notification: Notification) {
        AudioEngine.shared.shutdown()
    }
}
