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
    @Published public private(set) var hiddenApps: [HiddenApp] = []
    @Published public private(set) var outputDevices: [AudioDevice] = []
    @Published public private(set) var isDucking = false
    public private(set) var preferredOutputUID: String?

    /// Set by the panel while the output slider is being dragged so polling does not fight it.
    public var isEditingOutputVolume = false

    private let store: LevelStore
    private let preferences: AppPreferences
    private let tapManager = TapManager()
    private var outputUID: String?
    private var outputDeviceID: AudioObjectID = 0
    private var timer: Timer?
    private var meterTimer: Timer?
    private var started = false
    private var lastHotKeyBundleID: String?
    private var ducking = DuckingPolicy()
    public private(set) var duckingEnabled: Bool
    private static let duckingKey = "com.mardinli.tapmix.duckingEnabled"
    private static let preferredOutputKey = "com.mardinli.tapmix.preferredOutputUID"
    private var knownOutputUIDs: Set<String> = []

    init(store: LevelStore = LevelStore(), preferences: AppPreferences = AppPreferences()) {
        self.store = store
        self.preferences = preferences
        duckingEnabled = UserDefaults.standard.object(forKey: Self.duckingKey) as? Bool ?? true
        preferredOutputUID = UserDefaults.standard.string(forKey: Self.preferredOutputKey)
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

        let meterTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickMeters()
            }
        }
        RunLoop.main.add(meterTimer, forMode: .common)
        self.meterTimer = meterTimer
    }

    public func shutdown() {
        started = false
        timer?.invalidate()
        timer = nil
        meterTimer?.invalidate()
        meterTimer = nil
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
        tapManager.setGain(effectiveGain(level, bundleID: bundleID), for: bundleID)
        updateRow(bundleID, volume: level.volume)
    }

    public func setPinned(_ bundleID: String, _ pinned: Bool, name: String) {
        var preference = preferences.preference(for: bundleID)
        preference.pinned = pinned
        preference.name = name
        preferences.set(preference, for: bundleID)
        refresh()
    }

    public func setIgnored(_ bundleID: String, _ ignored: Bool, name: String? = nil) {
        var preference = preferences.preference(for: bundleID)
        preference.ignored = ignored
        if let name {
            preference.name = name
        }
        preferences.set(preference, for: bundleID)
        refresh()
    }

    public func setRoute(_ bundleID: String, _ outputUID: String?) {
        var level = store.level(for: bundleID)
        level.outputUID = outputUID
        store.set(level, for: bundleID)
        updateRow(bundleID, routeUID: outputUID)
        refresh()
    }

    public func setEQ(_ bundleID: String, _ settings: EQSettings) {
        var level = store.level(for: bundleID)
        level.eq = settings
        store.set(level, for: bundleID)
        tapManager.setEQ(settings, for: bundleID)
        updateRow(bundleID, eq: settings)
    }

    public func setBoost(_ bundleID: String, _ boost: Float) {
        var level = store.level(for: bundleID)
        level.boost = min(max(boost, 1), 4)
        store.set(level, for: bundleID)
        tapManager.setGain(effectiveGain(level, bundleID: bundleID), for: bundleID)
        updateRow(bundleID, boost: level.boost)
    }

    public func toggleMute(_ bundleID: String) {
        var level = store.level(for: bundleID)
        level.muted.toggle()
        store.set(level, for: bundleID)
        tapManager.setGain(effectiveGain(level, bundleID: bundleID), for: bundleID)
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

    public func setPreferredOutput(_ uid: String?) {
        preferredOutputUID = uid
        UserDefaults.standard.set(uid, forKey: Self.preferredOutputKey)

        if let uid, let device = outputDevices.first(where: { $0.uid == uid }) {
            AudioSystem.setDefaultOutputDevice(device.objectID)
            reloadOutput()
        }
        knownOutputUIDs = Set(outputDevices.map(\.uid))
        refresh()
    }

    public func setDuckingEnabled(_ enabled: Bool) {
        duckingEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.duckingKey)
        updateDucking()
        refresh()
    }

    // MARK: - Global hotkeys

    public func stepActiveVolume(by delta: Float) -> ActiveVolumeState? {
        guard let bundleID = activeBundleID(),
              let row = apps.first(where: { $0.bundleID == bundleID })
        else { return nil }

        lastHotKeyBundleID = bundleID
        var level = store.level(for: bundleID)
        level.volume = min(max(row.volume + delta, 0), 2)
        level.muted = false
        store.set(level, for: bundleID)
        tapManager.setGain(level.gain, for: bundleID)
        updateRow(bundleID, volume: level.volume, muted: false)
        return ActiveVolumeState(
            bundleID: bundleID,
            name: row.name,
            volume: level.volume,
            muted: false
        )
    }

    public func toggleActiveMute() -> ActiveVolumeState? {
        guard let bundleID = activeBundleID(),
              let row = apps.first(where: { $0.bundleID == bundleID })
        else { return nil }

        lastHotKeyBundleID = bundleID
        var level = store.level(for: bundleID)
        level.muted.toggle()
        store.set(level, for: bundleID)
        tapManager.setGain(effectiveGain(level, bundleID: bundleID), for: bundleID)
        updateRow(bundleID, muted: level.muted)
        return ActiveVolumeState(
            bundleID: bundleID,
            name: row.name,
            volume: level.volume,
            muted: level.muted
        )
    }

    private func activeBundleID() -> String? {
        ActiveAppSelector.bundleID(
            apps: apps,
            frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            lastActive: lastHotKeyBundleID
        )
    }

    // MARK: - Polling

    private func tick() {
        guard started else { return }
        reloadOutput()
        updateDucking()
        refresh()
    }

    private func updateDucking() {
        guard duckingEnabled else {
            let wasDucking = isDucking
            ducking.reset()
            isDucking = false
            if wasDucking {
                applyAllGains()
            }
            return
        }

        let wasDucking = isDucking
        isDucking = ducking.update(
            micActive: AudioSystem.inputIsActive(),
            frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            now: Date()
        )
        if wasDucking != isDucking {
            applyAllGains()
        }
    }

    private func effectiveGain(_ level: AppLevel, bundleID: String) -> Float {
        guard isDucking, !ducking.isExempt(bundleID: bundleID) else { return level.gain }
        return level.gain * DuckingPolicy.duckFactor
    }

    private func applyAllGains() {
        for bundleID in tapManager.activeBundleIDs {
            let level = store.level(for: bundleID)
            tapManager.setGain(effectiveGain(level, bundleID: bundleID), for: bundleID)
        }
    }

    private func applyPreferredOutput(devices: [AudioDevice]) {
        let available = Set(devices.map(\.uid))
        let newlyAvailable = available.subtracting(knownOutputUIDs)
        knownOutputUIDs = available

        guard let target = DevicePriority.outputDeviceToActivate(
            preferredUID: preferredOutputUID,
            currentUID: outputUID,
            availableUIDs: available,
            newlyAvailable: newlyAvailable
        ), let device = devices.first(where: { $0.uid == target })
        else { return }

        AudioSystem.setDefaultOutputDevice(device.objectID)
    }

    private func tickMeters() {
        guard started, !apps.isEmpty else { return }
        for index in apps.indices {
            let peak = tapManager.peakLevel(for: apps[index].bundleID)
            let previous = apps[index].level
            let next = max(peak, previous * 0.7)
            let value = next < 0.01 ? 0 : next
            if abs(value - previous) > 0.005 {
                apps[index].level = value
            }
        }
    }

    private func reloadOutput() {
        guard let device = AudioSystem.defaultOutputDevice() else {
            outputName = "No output device"
            outputUID = nil
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
        let devices = AudioSystem.outputDevices()
        if devices != outputDevices {
            outputDevices = devices
        }
        applyPreferredOutput(devices: devices)
        let availableUIDs = Set(devices.map(\.uid))
        let groups = AudioCatalog.groups(
            processes: processes,
            running: running,
            levels: store.allLevels,
            activeBundleIDs: tapManager.activeBundleIDs,
            pinnedBundleIDs: preferences.pinnedBundleIDs,
            ignoredBundleIDs: preferences.ignoredBundleIDs
        )

        for group in groups {
            tapManager.setGain(
                effectiveGain(group.level, bundleID: group.bundleID),
                for: group.bundleID
            )
        }

        var desired: [TapManager.DesiredTap] = []
        for group in groups {
            let route = group.level.outputUID.flatMap { availableUIDs.contains($0) ? $0 : nil }
            guard let target = route ?? outputUID else { continue }

            for processID in group.processObjectIDs
            where group.playingProcessObjectIDs.contains(processID)
                || tapManager.activeProcessIDs.contains(processID)
            {
                desired.append(
                    TapManager.DesiredTap(
                        processObjectID: processID,
                        bundleID: group.bundleID,
                        displayName: group.name,
                        outputUID: target
                    )
                )
            }
        }

        if outputUID == nil, desired.isEmpty {
            tapManager.stopAll()
        } else {
            tapManager.sync(desired: desired)
        }

        let previousLevels = Dictionary(uniqueKeysWithValues: apps.map { ($0.bundleID, $0.level) })
        apps = groups.map { group in
            var row = group.row
            row.level = previousLevels[group.bundleID] ?? 0
            return row
        }
        hiddenApps = preferences.all
            .filter { $0.value.ignored }
            .map { HiddenApp(bundleID: $0.key, name: $0.value.name ?? $0.key) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        switch tapManager.health {
        case .ok:
            errorMessage = nil
        case let .stalled(_, message):
            errorMessage = message
        }
    }

    private func updateRow(
        _ bundleID: String,
        volume: Float? = nil,
        muted: Bool? = nil,
        boost: Float? = nil,
        eq: EQSettings? = nil,
        routeUID: String? = nil
    ) {
        guard let index = apps.firstIndex(where: { $0.bundleID == bundleID }) else { return }
        if let volume {
            apps[index].volume = volume
        }
        if let muted {
            apps[index].muted = muted
        }
        if let boost {
            apps[index].boost = boost
        }
        if let eq {
            apps[index].eq = eq
        }
        if let routeUID {
            apps[index].routeUID = routeUID
        }
    }
}
