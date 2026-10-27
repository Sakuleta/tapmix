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
    private var taps: [AudioObjectID: TapController] = [:]
    private var failures: [AudioObjectID: Date] = [:]
    private var outputUID: String?
    private var outputDeviceID: AudioObjectID = 0
    private var timer: Timer?
    private var started = false
    private var captureBlocked = false

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
        stopAllTaps()
    }

    public func retry() {
        captureBlocked = false
        errorMessage = nil
        failures.removeAll()
        refresh()
    }

    // MARK: - User actions

    public func setVolume(_ bundleID: String, _ volume: Double) {
        var level = store.level(for: bundleID)
        level.volume = Float(min(max(volume, 0), 2))
        store.set(level, for: bundleID)
        apply(level, to: bundleID)
        updateRow(bundleID, volume: level.volume)
    }

    public func toggleMute(_ bundleID: String) {
        var level = store.level(for: bundleID)
        level.muted.toggle()
        store.set(level, for: bundleID)
        apply(level, to: bundleID)
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
                stopAllTaps()
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

        if outputUID != uid {
            outputUID = uid
            stopAllTaps()
        }
    }

    private func refresh() {
        let processes = AudioSystem.processes().filter { !$0.bundleID.isEmpty }
        let alive = Set(processes.map(\.objectID))

        for (objectID, tap) in taps where !alive.contains(objectID) {
            tap.stop()
            taps[objectID] = nil
            failures[objectID] = nil
        }

        let running = NSWorkspace.shared.runningApplications
        var groups: [String: [AudioProcess]] = [:]
        var identities: [String: AppIdentity] = [:]

        for process in processes {
            guard let identity = AppResolver.resolve(process, running: running) else { continue }
            groups[identity.bundleID, default: []].append(process)
            identities[identity.bundleID] = identity
        }

        var rows: [AppRow] = []
        var playingObjects: Set<AudioObjectID> = []

        for (bundleID, bundleProcesses) in groups {
            guard let identity = identities[bundleID] else { continue }
            let level = store.level(for: bundleID)
            let playing = bundleProcesses.contains { $0.isPlaying }
            let hasTaps = taps.values.contains { $0.bundleID == bundleID }

            // Keep the panel focused: show apps that are audible, were adjusted before,
            // or still have an active tap. Idle system processes stay hidden.
            guard playing || hasTaps || store.hasLevel(for: bundleID) else { continue }

            if playing {
                playingObjects.formUnion(bundleProcesses.filter(\.isPlaying).map(\.objectID))
            }

            rows.append(
                AppRow(
                    bundleID: bundleID,
                    name: identity.name,
                    icon: identity.icon,
                    isPlaying: playing,
                    volume: level.volume,
                    muted: level.muted
                )
            )

            for process in bundleProcesses where process.isPlaying {
                if let tap = taps[process.objectID] {
                    tap.setGain(level.gain)
                } else if let outputUID, !captureBlocked, shouldAttempt(process.objectID) {
                    let tap = TapController(
                        processObjectID: process.objectID,
                        bundleID: bundleID,
                        outputDeviceUID: outputUID
                    )
                    do {
                        try tap.start()
                        tap.setGain(level.gain)
                        taps[process.objectID] = tap
                        failures[process.objectID] = nil
                    } catch {
                        failures[process.objectID] = Date()
                        if errorMessage == nil {
                            errorMessage = error.localizedDescription
                                + " Allow “Tapmix” in System Settings → Privacy & Security → Screen & System Audio Recording, then press Retry."
                        }
                    }
                }
            }
        }

        apps = rows.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        checkHealth(playing: playingObjects)
    }

    /// Core Audio can return success but deliver no callbacks when audio-capture
    /// permission is denied. Detect that state instead of silently doing nothing.
    private func checkHealth(playing: Set<AudioObjectID>) {
        guard errorMessage == nil else { return }

        for (objectID, tap) in taps where playing.contains(objectID) {
            guard tap.callbackCount == 0,
                  Date().timeIntervalSince(tap.createdAt) > 6
            else { continue }

            stopAllTaps()
            captureBlocked = true
            failures[objectID] = Date()
            errorMessage = "macOS is not delivering audio for “\(tap.bundleID)”. Allow “Tapmix” in System Settings → Privacy & Security → Screen & System Audio Recording, then press Retry."
            return
        }
    }

    private func shouldAttempt(_ objectID: AudioObjectID) -> Bool {
        guard let failed = failures[objectID] else { return true }
        return Date().timeIntervalSince(failed) > 10
    }

    private func apply(_ level: AppLevel, to bundleID: String) {
        for tap in taps.values where tap.bundleID == bundleID {
            tap.setGain(level.gain)
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

    private func stopAllTaps() {
        for tap in taps.values {
            tap.stop()
        }
        taps.removeAll()
    }
}
