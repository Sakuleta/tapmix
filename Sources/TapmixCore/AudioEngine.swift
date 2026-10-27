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
    @Published public private(set) var scenes: [MixScene] = []
    @Published public private(set) var eqPresets: [SavedEQPreset] = []
    @Published public private(set) var recordingBundleIDs: Set<String> = []
    public private(set) var preferredOutputUID: String?

    /// Set by the panel while the output slider is being dragged so polling does not fight it.
    public var isEditingOutputVolume = false

    private let store: LevelStore
    private let preferences: AppPreferences
    private let sceneStore: SceneStore
    private let eqPresetStore: EQPresetStore
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
    private var systemListeners: [AudioSystem.PropertyListener] = []
    private var processListeners: [AudioObjectID: AudioSystem.PropertyListener] = [:]

    init(
        store: LevelStore = LevelStore(),
        preferences: AppPreferences = AppPreferences(),
        sceneStore: SceneStore = SceneStore(),
        eqPresetStore: EQPresetStore = EQPresetStore()
    ) {
        self.store = store
        self.preferences = preferences
        self.sceneStore = sceneStore
        self.eqPresetStore = eqPresetStore
        scenes = sceneStore.scenes
        eqPresets = eqPresetStore.presets
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

        installListeners()
    }

    public func shutdown() {
        started = false
        timer?.invalidate()
        timer = nil
        meterTimer?.invalidate()
        meterTimer = nil
        removeListeners()
        tapManager.fadeOutAndStop()
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

    public func setBalance(_ bundleID: String, _ balance: Float) {
        var level = store.level(for: bundleID)
        level.balance = min(max(balance, -1), 1)
        store.set(level, for: bundleID)
        tapManager.setBalance(level.balance, for: bundleID)
        updateRow(bundleID, balance: level.balance)
    }

    public func setMono(_ bundleID: String, _ enabled: Bool) {
        var level = store.level(for: bundleID)
        level.mono = enabled
        store.set(level, for: bundleID)
        tapManager.setMono(enabled, for: bundleID)
        updateRow(bundleID, mono: enabled)
    }

    public func setNightMode(_ bundleID: String, _ enabled: Bool) {
        var level = store.level(for: bundleID)
        level.nightMode = enabled
        store.set(level, for: bundleID)
        tapManager.setNightMode(enabled, for: bundleID)
        updateRow(bundleID, nightMode: enabled)
    }

    public func setEQ(_ bundleID: String, _ settings: EQSettings) {
        var level = store.level(for: bundleID)
        level.eq = settings
        store.set(level, for: bundleID)
        tapManager.setEQ(settings, for: bundleID)
        updateRow(bundleID, eq: settings)
    }

    public func setAudioUnit(_ bundleID: String, _ selection: AudioUnitSelection?) {
        var level = store.level(for: bundleID)
        level.audioUnit = selection
        store.set(level, for: bundleID)
        tapManager.setAudioUnit(selection, for: bundleID)
        refresh()
    }

    public func setBoost(_ bundleID: String, _ boost: Float) {
        var level = store.level(for: bundleID)
        level.boost = min(max(boost, 1), 4)
        store.set(level, for: bundleID)
        tapManager.setGain(effectiveGain(level, bundleID: bundleID), for: bundleID)
        updateRow(bundleID, boost: level.boost)
    }

    public func setMuted(_ bundleID: String, _ muted: Bool) {
        var level = store.level(for: bundleID)
        level.muted = muted
        store.set(level, for: bundleID)
        tapManager.setGain(effectiveGain(level, bundleID: bundleID), for: bundleID)
        updateRow(bundleID, muted: muted)
    }

    public func toggleMute(_ bundleID: String) {
        setMuted(bundleID, !store.level(for: bundleID).muted)
    }

    public func stepVolume(_ bundleID: String, by delta: Float) {
        var level = store.level(for: bundleID)
        level.volume = min(max(level.volume + delta, 0), 2)
        level.muted = false
        store.set(level, for: bundleID)
        tapManager.setGain(effectiveGain(level, bundleID: bundleID), for: bundleID)
        updateRow(bundleID, volume: level.volume, muted: false)
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

    public func isRecording(_ bundleID: String) -> Bool {
        recordingBundleIDs.contains(bundleID)
    }

    @discardableResult
    public func startRecording(_ bundleID: String, to url: URL) -> Bool {
        let urls = tapManager.startRecording(bundleID: bundleID, baseURL: url)
        guard !urls.isEmpty else { return false }
        syncRecordingState()
        return true
    }

    public func stopRecording(_ bundleID: String) {
        tapManager.stopRecording(bundleID: bundleID)
        syncRecordingState()
    }

    /// Recording state has one owner: the tap that owns the recorder.
    private func syncRecordingState() {
        let current = tapManager.recordingBundleIDs
        if recordingBundleIDs != current {
            recordingBundleIDs = current
        }
    }

    public func saveEQPreset(_ name: String, for bundleID: String) {
        eqPresetStore.save(name: name, settings: store.level(for: bundleID).eq)
        eqPresets = eqPresetStore.presets
    }

    public func deleteEQPreset(_ id: UUID) {
        eqPresetStore.delete(id)
        eqPresets = eqPresetStore.presets
    }

    public func saveScene(named name: String) {
        sceneStore.save(name: name, levels: store.allLevels)
        scenes = sceneStore.scenes
    }

    public func applyScene(_ scene: MixScene) {
        for (bundleID, level) in scene.levels {
            store.set(level, for: bundleID)
            tapManager.setGain(effectiveGain(level, bundleID: bundleID), for: bundleID)
            tapManager.setEQ(level.eq, for: bundleID)
            tapManager.setNightMode(level.nightMode, for: bundleID)
            tapManager.setBalance(level.balance, for: bundleID)
            tapManager.setMono(level.mono, for: bundleID)
            tapManager.setAudioUnit(level.audioUnit, for: bundleID)
        }
        refresh()
    }

    public func deleteScene(_ id: UUID) {
        sceneStore.delete(id)
        scenes = sceneStore.scenes
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
        tapManager.setGain(effectiveGain(level, bundleID: bundleID), for: bundleID)
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

    private func installListeners() {
        let systemSelectors: [AudioObjectPropertySelector] = [
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyProcessObjectList
        ]
        for selector in systemSelectors {
            let listener = AudioSystem.addListener(AudioSystem.systemObject, selector) { [weak self] in
                Task { @MainActor in self?.refreshNow() }
            }
            if let listener {
                systemListeners.append(listener)
            }
        }
    }

    private func syncProcessListeners(_ processIDs: [AudioObjectID]) {
        let alive = Set(processIDs)
        for (id, listener) in Array(processListeners) where !alive.contains(id) {
            AudioSystem.removeListener(listener)
            processListeners[id] = nil
        }
        for id in processIDs where processListeners[id] == nil {
            let listener = AudioSystem.addListener(id, kAudioProcessPropertyIsRunningOutput) { [weak self] in
                Task { @MainActor in self?.refreshNow() }
            }
            if let listener {
                processListeners[id] = listener
            }
        }
    }

    private func removeListeners() {
        for listener in systemListeners {
            AudioSystem.removeListener(listener)
        }
        systemListeners.removeAll()
        for listener in processListeners.values {
            AudioSystem.removeListener(listener)
        }
        processListeners.removeAll()
    }

    private func refreshNow() {
        guard started else { return }
        reloadOutput()
        updateDucking()
        refresh()
    }

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
            inputBundleIDs: AudioSystem.inputBundleIDs(),
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
        // A read failure is not "nothing is playing": keep the current rows and
        // taps until the HAL answers again.
        let processList = AudioSystem.processes()
        let processes = processList ?? []
        if processList != nil {
            syncProcessListeners(processes.map(\.objectID))
        }
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
            tapManager.setAudioUnit(group.level.audioUnit, for: group.bundleID)
        }

        let plan = TapPlan.make(
            groups: groups,
            availableUIDs: availableUIDs,
            outputUID: outputUID,
            activeProcessIDs: tapManager.activeProcessIDs,
            processListReadable: processList != nil
        )
        if plan.isComplete {
            if outputUID == nil, plan.taps.isEmpty {
                tapManager.stopAll()
            } else {
                tapManager.sync(desired: plan.taps)
            }
        }

        if processList != nil {
            let previousLevels = Dictionary(uniqueKeysWithValues: apps.map { ($0.bundleID, $0.level) })
            apps = groups.map { group in
                var row = group.row
                row.level = previousLevels[group.bundleID] ?? 0
                return row
            }
        }
        syncRecordingState()
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
        routeUID: String? = nil,
        nightMode: Bool? = nil,
        balance: Float? = nil,
        mono: Bool? = nil
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
        if let nightMode {
            apps[index].nightMode = nightMode
        }
        if let balance {
            apps[index].balance = balance
        }
        if let mono {
            apps[index].mono = mono
        }
    }
}
