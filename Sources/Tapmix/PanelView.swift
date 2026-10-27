import AppKit
import TapmixCore
import SwiftUI
import UniformTypeIdentifiers

struct PanelView: View {
    @ObservedObject var engine: AudioEngine
    @ObservedObject private var hotkeys = HotKeyController.shared
    @ObservedObject private var loginItem = LoginItemController.shared
    @State private var search = ""
    @State private var sceneName = ""
    @State private var showingSaveScene = false

    var body: some View {
        VStack(spacing: 0) {
            header
            outputSection

            if let error = engine.errorMessage {
                errorBanner(error)
            }

            appSection
            Hairline(inset: 0)
            footer
        }
        .frame(width: 360, height: panelHeight)
        .background(PanelSurface())
        .background(MenuBarAnchor(size: CGSize(width: 360, height: panelHeight)))
        .onAppear { engine.setPanelVisible(true) }
        .onDisappear { engine.setPanelVisible(false) }
        .alert("Save current mix", isPresented: $showingSaveScene) {
            TextField("Name", text: $sceneName)
            Button("Save") {
                engine.saveScene(named: sceneName)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves levels, EQ, routing and night mode for every adjusted app.")
        }
    }

    private var filteredApps: [AppRow] {
        guard !search.isEmpty else { return engine.apps }
        return engine.apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var panelHeight: CGFloat {
        // Keep the panel height stable while searching so MenuBarExtra does not
        // resize (and leave a blank gap) on every keystroke.
        let visibleRows = min(max(engine.apps.count, 1), 6)
        return min(500, 214 + CGFloat(visibleRows) * 58)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 25))
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("Tapmix")
                    .font(.headline)
                Text("Per-app volume control")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button("Save current mix…") {
                    sceneName = "Scene \(engine.scenes.count + 1)"
                    showingSaveScene = true
                }
                if !engine.scenes.isEmpty {
                    Divider()
                    ForEach(engine.scenes) { scene in
                        Button(scene.name) {
                            engine.applyScene(scene)
                        }
                    }
                    Divider()
                    Menu("Delete scene") {
                        ForEach(engine.scenes) { scene in
                            Button(scene.name) {
                                engine.deleteScene(scene.id)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "theatermasks")
                    .font(.system(size: 12))
                    .frame(width: 22, height: 22)
                    .hoverHighlight()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Saved mixes")
            .accessibilityLabel("Saved mixes")

            Button {
                engine.retry()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .hoverHighlight()
            }
            .buttonStyle(PressableStyle())
            .foregroundStyle(.secondary)
            .help("Refresh audio apps")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var outputSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "hifispeaker.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Text(engine.outputName)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)

                Spacer()

                Text("\(Int((engine.outputVolume * 100).rounded()))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)

                Menu {
                    Button {
                        engine.setPreferredOutput(nil)
                    } label: {
                        if engine.preferredOutputUID == nil {
                            Label("Follow macOS", systemImage: "checkmark")
                        } else {
                            Text("Follow macOS")
                        }
                    }
                    Divider()
                    ForEach(engine.outputDevices) { device in
                        Button {
                            engine.setPreferredOutput(device.uid)
                        } label: {
                            if engine.preferredOutputUID == device.uid {
                                Label(device.name, systemImage: "checkmark")
                            } else {
                                Text(device.name)
                            }
                        }
                    }
                } label: {
                    Image(systemName: engine.preferredOutputUID == nil ? "arrow.left.arrow.right" : "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(engine.preferredOutputUID == nil ? .secondary : Color.accentColor)
                        .frame(width: 20, height: 20)
                        .hoverHighlight()
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Preferred output device")
                .accessibilityLabel("Preferred output device")
            }

            HStack(spacing: 10) {
                Button {
                    engine.toggleOutputMute()
                } label: {
                    Image(systemName: engine.outputMuted ? "speaker.slash.fill" : "speaker.fill")
                        .font(.system(size: 12))
                        .frame(width: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(engine.outputMuted ? .red : .secondary)
                .accessibilityLabel(engine.outputMuted ? "Unmute output" : "Mute output")

                VolumeSlider(
                    value: Binding(
                        get: { engine.outputVolume },
                        set: { engine.setOutputVolume($0) }
                    ),
                    range: 0 ... 1,
                    label: "Output volume",
                    valueDescription: "\(Int((engine.outputVolume * 100).rounded())) percent"
                ) { editing in
                    engine.isEditingOutputVolume = editing
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .panelCard()
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private var appSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("APPS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                SearchField(text: $search)
                    .frame(width: 116)
                    .accessibilityLabel("Search apps")
                Text("\(filteredApps.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 5)

            if engine.apps.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "waveform")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No apps playing audio")
                        .font(.callout.weight(.medium))
                    Text("Start playback in any app and it appears here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
            } else if filteredApps.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 19, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No apps match “\(search)”")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredApps) { app in
                            AppRowView(app: app, engine: engine)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Audio capture needs permission", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)

            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Open Settings") {
                    openPrivacySettings()
                }
                Button("Retry") {
                    engine.retry()
                }
            }
            .font(.caption)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.09))
    }

    private var footer: some View {
        HStack(spacing: 2) {
            Text("Open source · MIT")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Menu {
                Button("Check for Updates…") {
                    UpdateController.shared.checkForUpdates()
                }
                Divider()
                Toggle("Launch at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .hoverHighlight()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Launch at login")
            .accessibilityLabel("Launch at login")
            Menu {
                ForEach(HotKeyModifiers.allCases) { option in
                    Button {
                        hotkeys.setModifiers(option)
                    } label: {
                        if hotkeys.modifiers == option {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 10))
                    .foregroundStyle(hotkeys.modifiers == .off ? .tertiary : .secondary)
                    .frame(width: 22, height: 22)
                    .hoverHighlight()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Global hotkey modifiers")
            .accessibilityLabel("Hotkey modifiers")
            Menu {
                Toggle("Duck other apps during calls", isOn: Binding(
                    get: { engine.duckingEnabled },
                    set: { engine.setDuckingEnabled($0) }
                ))
            } label: {
                Image(systemName: engine.isDucking ? "speaker.wave.1.fill" : "speaker.wave.1")
                    .font(.system(size: 10))
                    .foregroundStyle(engine.isDucking ? Color.orange : .secondary)
                    .frame(width: 22, height: 22)
                    .hoverHighlight()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Duck other apps while a call app uses the microphone")
            .accessibilityLabel("Call ducking")
            if !engine.hiddenApps.isEmpty {
                Menu {
                    ForEach(engine.hiddenApps) { app in
                        Button("Show \(app.name)") {
                            engine.setIgnored(app.bundleID, false)
                        }
                    }
                } label: {
                    Label("\(engine.hiddenApps.count)", systemImage: "eye.slash")
                        .font(.system(size: 10))
                        .frame(height: 22)
                        .hoverHighlight()
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Hidden apps")
                .accessibilityLabel("Hidden apps")
            }
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(PressableStyle())
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .hoverHighlight(radius: 5)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .alert("Could not update login item", isPresented: Binding(
            get: { loginItem.errorMessage != nil },
            set: { presented in
                if !presented {
                    loginItem.clearError()
                }
            }
        )) {
            Button("OK") { loginItem.clearError() }
        } message: {
            Text(loginItem.errorMessage ?? "")
        }
    }

    private func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
