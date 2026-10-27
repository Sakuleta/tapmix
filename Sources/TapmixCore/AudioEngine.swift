import AppKit
import Combine
import CoreAudio
import Foundation

@MainActor
public final class AudioEngine: ObservableObject {
    public static let shared = AudioEngine()

    @Published public private(set) var apps: [AppRow] = []
    @Published public private(set) var outputName = "Output"
    @Published public private(set) var outputVolume: Double = 0
    @Published public private(set) var outputMuted = false
    @Published public private(set) var errorMessage: String?

    /// Set by the panel while the output slider is being dragged so polling does not fight it.
    public var isEditingOutputVolume = false

    private let store: LevelStore
    private let tapManager = TapManager()
    private var outputUID: String?
    private var outputDeviceID: AudioObjectID = 0
    private var timer: Timer?
    private var started = false

    init(store: LevelStore = LevelStore()) {
        self.store = store
    }

    // MARK: - Lifecycle

    public func start() {
        guard !started else { return }
        started = true
        reloadOutput()
        refresh()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func shutdown() {
        started = false
        timer?.invalidate()
        timer = nil
        tapManager.stopAll()
    }

    public func retry() {
        tapManager.retry()
        errorMessage = nil
        refresh()
    }

    // MARK: - User actions

    public func setVolume(_ bundleID: String, _ volume: Double) {
        var level = store.level(for: bundleID)
        level.volume = Float(min(max(volume, 0), 2))
        store.set(level, for: bundleID)
        tapManager.setGain(level.gain, for: bundleID)
        updateRow(bundleID, volume: level.volume)
    }

    public func toggleMute(_ bundleID: String) {
        var level = store.level(for: bundleID)
        level.muted.toggle()
        store.set(level, for: bundleID)
        tapManager.setGain(level.gain, for: bundleID)
        updateRow(bundleID, muted: level.muted)
    }

    public func setOutputVolume(_ volume: Double) {
        guard outputDeviceID != 0 else { return }
        let value = Float(min(max(volume, 0), 1))
        AudioSystem.setOutputVolume(outputDeviceID, value)
        outputVolume = Double(value)
        if value > 0, outputMuted {
            setOutputMuted(false)
        }
    }

    public func setOutputMuted(_ muted: Bool) {
        guard outputDeviceID != 0 else { return }
        AudioSystem.setOutputMuted(outputDeviceID, muted)
        outputMuted = muted
    }

    public func toggleOutputMute() {
        setOutputMuted(!outputMuted)
    }

    // MARK: - Polling

    private func tick() {
        guard started else { return }
        reloadOutput()
        refresh()
    }

    private func reloadOutput() {
        guard let device = AudioSystem.defaultOutputDevice() else {
            outputName = "No output device"
            if outputUID != nil {
                outputUID = nil
                tapManager.stopAll()
            }
            return
        }

        let uid = AudioSystem.deviceUID(device) ?? String(device)
        outputDeviceID = device
        outputName = AudioSystem.deviceName(device) ?? "Output"

        if !isEditingOutputVolume, let volume = AudioSystem.outputVolume(device) {
            outputVolume = Double(volume)
        }
        outputMuted = AudioSystem.outputMuted(device) ?? false

        outputUID = uid
    }

    private func refresh() {
        let processes = AudioSystem.processes()
        let running = RunningAppDescriptor.snapshot(NSWorkspace.shared.runningApplications)
        let groups = AudioCatalog.groups(
            processes: processes,
            running: running,
            levels: store.allLevels,
            activeBundleIDs: tapManager.activeBundleIDs
        )

        for group in groups {
            tapManager.setGain(group.level.gain, for: group.bundleID)
        }

        var desired: [TapManager.DesiredTap] = []
        for group in groups {
            for processID in group.processObjectIDs
            where group.playingProcessObjectIDs.contains(processID)
                || tapManager.activeProcessIDs.contains(processID)
            {
                desired.append(
                    TapManager.DesiredTap(
                        processObjectID: processID,
                        bundleID: group.bundleID,
                        displayName: group.name
                    )
                )
            }
        }

        if let outputUID {
            tapManager.sync(desired: desired, outputUID: outputUID)
        } else {
            tapManager.stopAll()
        }

        apps = groups.map(\.row)

        switch tapManager.health {
        case .ok:
            errorMessage = nil
        case let .stalled(_, message):
            errorMessage = message
        }
    }

    private func updateRow(_ bundleID: String, volume: Float? = nil, muted: Bool? = nil) {
        guard let index = apps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        if let volume {
            apps[index].volume = volume
        }
        if let muted {
            apps[index].muted = muted
        }
    }
}
