import AppKit
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        AudioEngine.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AudioEngine.shared.shutdown()
    }
}
