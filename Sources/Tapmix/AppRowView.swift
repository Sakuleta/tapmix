import AppKit
import SwiftUI
import TapmixCore
import UniformTypeIdentifiers

struct AppRowView: View {
    let app: AppRow
    @ObservedObject var engine: AudioEngine
    @State private var showEQ = false
    @State private var showingAudioUnits = false
    @State private var audioUnits: [AudioUnitInfo] = []
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

                    if app.isInCall {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.green)
                            .help("In a call — audio plays untouched until the call ends")
                            .accessibilityLabel("In a call, volume control paused")
                    }

                    if engine.isRecording(app.bundleID) {
                        Image(systemName: "record.circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.red)
                            .help("Recording")
                            .accessibilityLabel("Recording")
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
                            .frame(width: 18, height: 18)
                            .hoverHighlight()
                    }
                    .buttonStyle(PressableStyle())
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
                            .frame(width: 20, height: 18)
                            .hoverHighlight()
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
                            .frame(width: 18, height: 18)
                            .hoverHighlight()
                    }
                    .buttonStyle(PressableStyle())
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
                            .frame(width: 18, height: 18)
                            .hoverHighlight()
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Output for \(app.name)")
                    .accessibilityLabel("Output for \(app.name)")

                    VolumeSlider(
                        value: Binding(
                            get: { Double(app.volume) },
                            set: { engine.setVolume(app.bundleID, $0) }
                        ),
                        range: 0 ... 2,
                        tint: app.volume > 1 || app.boost > 1 ? .orange : .accentColor,
                        label: "Volume for \(app.name)",
                        valueDescription: "\(Int((app.volume * 100).rounded())) percent"
                    )
                }

                LevelMeter(level: app.level)
                    .frame(height: 2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Design.rowRadius, style: .continuous)
                .fill(Color.primary.opacity(rowFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.rowRadius, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(app.isPlaying ? 0.07 : 0.04),
                    lineWidth: 0.5
                )
        )
        .opacity(app.isPlaying || app.pinned || hovering ? 1 : 0.62)
        .contentShape(RoundedRectangle(cornerRadius: Design.rowRadius, style: .continuous))
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: Design.hoverDuration), value: hovering)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: app.isPlaying)
        .contextMenu {
            Button(app.pinned ? "Unpin" : "Pin to Top") {
                engine.setPinned(app.bundleID, !app.pinned, name: app.name)
            }
            Divider()
            Button(engine.isRecording(app.bundleID) ? "Stop recording" : "Record audio…") {
                toggleRecording()
            }
            Divider()
            Button(app.audioUnit == nil ? "Audio Unit Effect…" : "Audio Unit Effect (on)…") {
                audioUnits = AudioUnitCatalog.effects()
                showingAudioUnits = true
            }
            Divider()
            Button("Hide from Tapmix") {
                engine.setIgnored(app.bundleID, true, name: app.name)
            }
        }
        .sheet(isPresented: $showingAudioUnits) {
            AudioUnitPickerView(
                units: audioUnits,
                selected: app.audioUnit
            ) { selection in
                engine.setAudioUnit(app.bundleID, selection)
            }
        }
    }

    private func toggleRecording() {
        if engine.isRecording(app.bundleID) {
            engine.stopRecording(app.bundleID)
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(app.name).wav"
        panel.allowedContentTypes = [.wav]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        if !engine.startRecording(app.bundleID, to: url) {
            let alert = NSAlert()
            alert.messageText = "Cannot record \(app.name)"
            alert.informativeText = "Start playback in the app first."
            alert.runModal()
        }
    }

    private var rowFill: Double {
        if hovering {
            return 0.1
        }
        return app.isPlaying ? 0.065 : 0.03
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

struct LevelMeter: View {
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
