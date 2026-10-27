import AppKit
import SwiftUI
import TapmixCore
import UniformTypeIdentifiers

struct EQPanel: View {
    let bundleID: String
    @ObservedObject var engine: AudioEngine
    @State private var settings: EQSettings
    @State private var nightMode: Bool
    @State private var balance: Float
    @State private var mono: Bool
    @State private var importing = false
    @State private var presetName = ""
    @State private var showingSavePreset = false
    @State private var showingFolderPicker = false
    @State private var showingCatalog = false
    @State private var catalogProfiles: [AutoEQProfile] = []
    @AppStorage("com.mardinli.tapmix.autoEQFolderPath") private var autoEQFolderPath = ""

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
                    if !engine.eqPresets.isEmpty {
                        Divider()
                        ForEach(engine.eqPresets) { preset in
                            Button(preset.name) {
                                settings = preset.settings
                                apply()
                            }
                        }
                    }
                    Divider()
                    Button("Save preset…") {
                        presetName = "Preset \(engine.eqPresets.count + 1)"
                        showingSavePreset = true
                    }
                    if !engine.eqPresets.isEmpty {
                        Menu("Delete preset") {
                            ForEach(engine.eqPresets) { preset in
                                Button(preset.name) {
                                    engine.deleteEQPreset(preset.id)
                                }
                            }
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            EQCurveView(settings: settings)

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
                Menu("AutoEQ") {
                    Button("Import file…") { importing = true }
                    Button("Browse folder…") { showingFolderPicker = true }
                    if !autoEQFolderPath.isEmpty {
                        Button("Open catalog") { loadCatalog() }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                if !settings.filters.isEmpty {
                    Text("\(settings.filters.count) filters")
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
        .alert("Save EQ preset", isPresented: $showingSavePreset) {
            TextField("Name", text: $presetName)
            Button("Save") {
                engine.saveEQPreset(presetName, for: bundleID)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the current bands and AutoEQ filters.")
        }
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
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [UTType.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            autoEQFolderPath = url.path
            catalogProfiles = AutoEQCatalog.scan(folder: url)
            showingCatalog = !catalogProfiles.isEmpty
        }
        .sheet(isPresented: $showingCatalog) {
            AutoEQCatalogView(profiles: catalogProfiles) { profile in
                let filters = AutoEQCatalog.filters(for: profile)
                guard !filters.isEmpty else { return }
                settings.filters = filters
                apply()
            }
        }
    }

    private func loadCatalog() {
        catalogProfiles = AutoEQCatalog.scan(
            folder: URL(fileURLWithPath: autoEQFolderPath)
        )
        showingCatalog = !catalogProfiles.isEmpty
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

struct EQCurveView: View {
    let settings: EQSettings

    var body: some View {
        ZStack {
            EQGridShape()
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            EQCurveShape(settings: settings)
                .stroke(Color.accentColor, lineWidth: 1.5)
        }
        .frame(width: 276, height: 72)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .accessibilityLabel("EQ response")
    }
}

struct EQGridShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for level in [-12, 0, 12] {
            let y = rect.midY - CGFloat(level) / 36 * rect.height
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

struct EQCurveShape: Shape {
    let settings: EQSettings

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = EQResponse.points(for: settings)
        guard points.count > 1 else { return path }

        for (index, decibels) in points.enumerated() {
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(points.count - 1)
            let clamped = min(max(CGFloat(decibels), -18), 18)
            let y = rect.midY - clamped / 36 * rect.height
            let point = CGPoint(x: x, y: y)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}
