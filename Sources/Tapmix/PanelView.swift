import AppKit
import TapmixCore
import SwiftUI
import UniformTypeIdentifiers

struct PanelView: View {
    @ObservedObject var engine: AudioEngine
    @ObservedObject private var hotkeys = HotKeyController.shared
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            outputSection
            divider

            if let error = engine.errorMessage {
                errorBanner(error)
            }

            appSection
            divider
            footer
        }
        .frame(width: 360, height: panelHeight)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var filteredApps: [AppRow] {
        guard !search.isEmpty else { return engine.apps }
        return engine.apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var panelHeight: CGFloat {
        let visibleRows = min(max(filteredApps.count, 1), 6)
        return min(500, 244 + CGFloat(visibleRows) * 58)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 1) {
                Text("Tapmix")
                    .font(.headline)
                Text("Per-app volume control")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                engine.retry()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Refresh audio apps")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var outputSection: some View {
        VStack(spacing: 7) {
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

                Slider(
                    value: Binding(
                        get: { engine.outputVolume },
                        set: { engine.setOutputVolume($0) }
                    ),
                    in: 0 ... 1
                ) { editing in
                    engine.isEditingOutputVolume = editing
                }
                .controlSize(.small)
                .accessibilityLabel("Output volume")
                .accessibilityValue("\(Int((engine.outputVolume * 100).rounded())) percent")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var appSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("APPS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.mini)
                    .frame(width: 96)
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
                Text("No matching apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredApps) { app in
                            AppRowView(app: app, engine: engine)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
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
        HStack {
            Text("Open source · MIT")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
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
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Duck other apps while the microphone is in use")
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
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var divider: some View {
        Divider().opacity(0.45)
    }

    private func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private struct AppRowView: View {
    let app: AppRow
    @ObservedObject var engine: AudioEngine
    @State private var showEQ = false

    var body: some View {
        HStack(spacing: 10) {
            icon

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(app.isPlaying ? Color.green : Color.secondary.opacity(0.25))
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)

                    Text(app.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if app.pinned {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Pinned")
                    }

                    Text("\(Int((app.volume * 100).rounded()))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(app.volume > 1 || app.boost > 1 ? .orange : .secondary)
                }

                HStack(spacing: 8) {
                    Button {
                        engine.toggleMute(app.bundleID)
                    } label: {
                        Image(systemName: app.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 10))
                            .frame(width: 14)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(app.muted ? .red : .secondary)
                    .help(app.muted ? "Unmute \(app.name)" : "Mute \(app.name)")
                    .accessibilityLabel(app.muted ? "Unmute \(app.name)" : "Mute \(app.name)")

                    Menu {
                        ForEach([1, 2, 3, 4], id: \.self) { value in
                            Button {
                                engine.setBoost(app.bundleID, Float(value))
                            } label: {
                                if Int(app.boost.rounded()) == value {
                                    Label("\(value)×", systemImage: "checkmark")
                                } else {
                                    Text("\(value)×")
                                }
                            }
                        }
                    } label: {
                        Text("\(Int(app.boost.rounded()))×")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(app.boost > 1 ? .orange : .secondary)
                            .frame(width: 18)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Volume boost (soft-limited)")
                    .accessibilityLabel("Volume boost for \(app.name)")

                    Button {
                        showEQ.toggle()
                    } label: {
                        Image(systemName: "slider.vertical.3")
                            .font(.system(size: 10))
                            .frame(width: 14)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(app.eq.isActive ? Color.accentColor : .secondary)
                    .help("Equalizer for \(app.name)")
                    .accessibilityLabel("Equalizer for \(app.name)")
                    .popover(isPresented: $showEQ, arrowEdge: .trailing) {
                        EQPanel(
                            bundleID: app.bundleID,
                            initial: app.eq,
                            initialNightMode: app.nightMode,
                            initialBalance: app.balance,
                            initialMono: app.mono,
                            engine: engine
                        )
                    }

                    Menu {
                        Button {
                            engine.setRoute(app.bundleID, nil)
                        } label: {
                            if app.routeUID == nil {
                                Label("System Default", systemImage: "checkmark")
                            } else {
                                Text("System Default")
                            }
                        }
                        Divider()
                        ForEach(engine.outputDevices) { device in
                            Button {
                                engine.setRoute(app.bundleID, device.uid)
                            } label: {
                                if app.routeUID == device.uid {
                                    Label(device.name, systemImage: "checkmark")
                                } else {
                                    Text(device.name)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "hifispeaker")
                            .font(.system(size: 10))
                            .foregroundStyle(app.routeUID == nil ? .secondary : Color.accentColor)
                            .frame(width: 14)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Output for \(app.name)")
                    .accessibilityLabel("Output for \(app.name)")

                    Slider(
                        value: Binding(
                            get: { Double(app.volume) },
                            set: { engine.setVolume(app.bundleID, $0) }
                        ),
                        in: 0 ... 2
                    )
                    .controlSize(.mini)
                    .tint(app.volume > 1 || app.boost > 1 ? .orange : .accentColor)
                    .accessibilityLabel("Volume for \(app.name)")
                    .accessibilityValue("\(Int((app.volume * 100).rounded())) percent")
                }

                LevelMeter(level: app.level)
                    .frame(height: 2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(app.isPlaying ? 0.065 : 0.03))
        )
        .opacity(app.isPlaying || app.pinned ? 1 : 0.6)
        .contextMenu {
            Button(app.pinned ? "Unpin" : "Pin to Top") {
                engine.setPinned(app.bundleID, !app.pinned, name: app.name)
            }
            Divider()
            Button("Hide from Tapmix") {
                engine.setIgnored(app.bundleID, true, name: app.name)
            }
        }
    }

    private var icon: some View {
        Group {
            if let appIcon = app.icon {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

private struct LevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(level > 0.9 ? Color.orange : Color.green.opacity(0.8))
                    .frame(width: proxy.size.width * CGFloat(min(max(level, 0), 1)))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct EQPanel: View {
    let bundleID: String
    @ObservedObject var engine: AudioEngine
    @State private var settings: EQSettings
    @State private var nightMode: Bool
    @State private var balance: Float
    @State private var mono: Bool
    @State private var importing = false

    init(
        bundleID: String,
        initial: EQSettings,
        initialNightMode: Bool,
        initialBalance: Float,
        initialMono: Bool,
        engine: AudioEngine
    ) {
        self.bundleID = bundleID
        self.engine = engine
        _settings = State(initialValue: initial)
        _nightMode = State(initialValue: initialNightMode)
        _balance = State(initialValue: initialBalance)
        _mono = State(initialValue: initialMono)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Equalizer", isOn: Binding(
                    get: { settings.enabled },
                    set: { enabled in
                        settings.enabled = enabled
                        apply()
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)

                Spacer()

                Menu("Presets") {
                    ForEach(EQPreset.allCases) { preset in
                        Button(preset.rawValue) {
                            settings = preset.settings
                            apply()
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            HStack {
                Toggle("Night mode", isOn: Binding(
                    get: { nightMode },
                    set: { enabled in
                        nightMode = enabled
                        engine.setNightMode(bundleID, enabled)
                    }
                ))
                .help("Lift quiet dialogue and tame loud peaks for late-night listening")

                Spacer()

                Toggle("Mono", isOn: Binding(
                    get: { mono },
                    set: { enabled in
                        mono = enabled
                        engine.setMono(bundleID, enabled)
                    }
                ))
                .help("Downmix both channels for a single earbud")
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            HStack(spacing: 6) {
                Text("L")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { Double(balance) },
                    set: { value in
                        balance = Float(value)
                        engine.setBalance(bundleID, balance)
                    }
                ), in: -1 ... 1)
                .controlSize(.mini)
                .accessibilityLabel("Balance for \(bundleID)")
                Text("R")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                if settings.filters.isEmpty {
                    Button("Import AutoEQ…") {
                        importing = true
                    }
                } else {
                    Text("\(settings.filters.count) AutoEQ filters")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") {
                        settings.filters = []
                        apply()
                    }
                }
            }
            .font(.caption)

            ForEach(0 ..< EQSettings.bandCount, id: \.self) { index in
                HStack(spacing: 6) {
                    Text(Self.label(index))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .leading)

                    Slider(value: Binding(
                        get: { Double(settings.gains[index]) },
                        set: { value in
                            settings.gains[index] = Float(value)
                            settings.enabled = true
                            apply()
                        }
                    ), in: Double(EQSettings.gainRange.lowerBound) ... Double(EQSettings.gainRange.upperBound))
                    .controlSize(.mini)

                    Text("\(Int(settings.gains[index].rounded()))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .trailing)
                }
            }

            HStack {
                Text("dB")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Flat") {
                    settings = EQSettings()
                    apply()
                }
                .font(.caption)
            }
        }
        .padding(12)
        .frame(width: 300)
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [UTType.plainText, UTType.data],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            let filters = EQFilterParser.parse(text)
            guard !filters.isEmpty else { return }
            settings.filters = filters
            apply()
        }
    }

    private func apply() {
        engine.setEQ(bundleID, settings)
    }

    private static func label(_ index: Int) -> String {
        let frequency = EQSettings.frequencies[index]
        return frequency >= 1000
            ? "\(Int(frequency / 1000))k"
            : "\(Int(frequency))"
    }
}
