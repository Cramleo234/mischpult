import AppKit
import CoreAudio
import MischpultCore
import ServiceManagement
import SwiftUI

/// Eine App in der Liste.
struct AppEntry: Identifiable {
    let id: String
    var name: String
    var bundleID: String?
    var appPID: pid_t
    var processObjectIDs: [AudioObjectID]
    var isPlaying: Bool
    var settings: AppSettings
    var icon: NSImage
    var level: Float = 0
    var error: String?
}

@MainActor
final class MixerStore: ObservableObject {
    @Published private(set) var apps: [AppEntry] = []
    @Published private(set) var outputs: [AudioDevice] = []
    @Published private(set) var inputs: [AudioDevice] = []
    @Published private(set) var defaultOutputID: AudioObjectID = 0
    @Published private(set) var defaultInputID: AudioObjectID = 0
    @Published var masterVolume: Float = 0
    @Published private(set) var masterHasVolume = false
    @Published private(set) var masterMuted = false
    @Published var inputVolume: Float = 0
    @Published private(set) var inputHasVolume = false
    @Published private(set) var permission = AudioPermission.status
    @Published var expandedApp: String?
    @Published var showAllApps: Bool {
        didSet {
            guard !isPreview else { return }
            defaults.set(showAllApps, forKey: "showAllApps")
            refreshApps()
        }
    }
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var launchAtLoginNeedsApproval = SMAppService.mainApp.status == .requiresApproval

    private let defaults = UserDefaults.standard
    private var settings: [String: AppSettings] = [:]
    private var taps: [String: AppTap] = [:]
    private var tapErrors: [String: String] = [:]
    private var lastChange: [String: Date] = [:]
    /// Apps, die in dieser Sitzung schon Ton abgespielt haben, bleiben sichtbar.
    private var seenPlaying: Set<String> = []
    private var listeners: [CAListener] = []
    private var timer: Timer?
    private var isVisible = false
    /// App-Symbole einmal laden statt bei jedem Neuzeichnen (20 × pro Sekunde).
    private var icons: [String: NSImage] = [:]
    private var lastTapAttempt: [String: Date] = [:]
    /// Prüfmodus (MISCHPULT_UIAUDIT): nur Beispieldaten, kein Zugriff auf Ton oder Geräte.
    let isPreview: Bool

    /// Steuerung mit Beispieldaten für den Prüfmodus.
    init(preview apps: [AppEntry], outputs: [AudioDevice], inputs: [AudioDevice]) {
        isPreview = true
        showAllApps = false
        self.apps = apps
        self.outputs = outputs
        self.inputs = inputs
        defaultOutputID = outputs.first?.id ?? 0
        defaultInputID = inputs.first?.id ?? 0
        masterVolume = 0.56
        masterHasVolume = true
        inputVolume = 0.64
        inputHasVolume = true
        permission = .granted
        for app in apps { settings[app.id] = app.settings }
    }

    /// Nur für den Prüfmodus: Zustand direkt setzen.
    func previewSet(apps: [AppEntry]? = nil, permission: AudioPermission.Status? = nil) {
        guard isPreview else { return }
        if let apps {
            self.apps = apps
            for app in apps { settings[app.id] = app.settings }
        }
        if let permission { self.permission = permission }
    }

    init() {
        isPreview = false
        showAllApps = defaults.bool(forKey: "showAllApps")
        if let data = defaults.data(forKey: "appSettings"),
           let stored = try? JSONDecoder().decode([String: AppSettings].self, from: data) {
            settings = stored
        }
        let system = AudioObjectID(kAudioObjectSystemObject)
        for selector in [kAudioHardwarePropertyProcessObjectList, kAudioHardwarePropertyDevices,
                         kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice] {
            if let listener = CAListener(object: system, address: CAProperty.address(selector),
                                         handler: { [weak self] in self?.refreshAll() }) {
                listeners.append(listener)
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopAllTaps() }
        }
        refreshAll()
        scheduleTimer()
    }

    // MARK: Sichtbarkeit / Takt

    func setVisible(_ visible: Bool) {
        guard !isPreview else { return }
        isVisible = visible
        if visible {
            checkPermission()
            refreshLaunchAtLogin()
            refreshAll()
        }
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        // Offen: flüssige Pegelanzeige. Geschlossen: nur gelegentlich nach neuen Apps sehen.
        let interval: TimeInterval = isVisible ? 1.0 / 20 : 3
        var ticks = 0
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                ticks += 1
                if self.isVisible {
                    self.updateLevels()
                    if ticks % 10 == 0 { self.refreshApps(); self.refreshVolumes() }
                    if ticks % 40 == 0 { self.checkPermission() }
                } else {
                    self.refreshApps()
                    if ticks % 5 == 0 { self.checkPermission() }
                }
            }
        }
    }

    // MARK: Geräte

    func refreshAll() {
        guard !isPreview else { return }
        refreshDevices()
        refreshApps()
    }

    private func refreshDevices() {
        let all = AudioDevices.all()
        outputs = all.filter(\.hasOutput)
        inputs = all.filter(\.hasInput)
        let newDefault = AudioDevices.defaultDevice()
        let outputChanged = newDefault != defaultOutputID
        defaultOutputID = newDefault
        defaultInputID = AudioDevices.defaultDevice(input: true)
        refreshVolumes()
        if outputChanged {
            // Apps, die der Systemausgabe folgen, auf das neue Gerät umziehen.
            for (key, tap) in taps where settings[key]?.outputUID == nil {
                if tap.outputUID != AudioDevices.uid(of: newDefault) { removeTap(key) }
            }
        }
    }

    private func refreshVolumes() {
        let volume = AudioDevices.volume(defaultOutputID)
        masterHasVolume = volume != nil
        masterVolume = volume ?? 1
        masterMuted = AudioDevices.isMuted(defaultOutputID)
        let input = AudioDevices.volume(defaultInputID, input: true)
        inputHasVolume = input != nil
        inputVolume = input ?? 1
    }

    var defaultOutput: AudioDevice? { outputs.first { $0.id == defaultOutputID } }
    var defaultInput: AudioDevice? { inputs.first { $0.id == defaultInputID } }

    func selectOutput(_ device: AudioDevice) {
        if isPreview { defaultOutputID = device.id; return }
        AudioDevices.setDefaultDevice(device.id)
        refreshAll()
    }

    func selectInput(_ device: AudioDevice) {
        if isPreview { defaultInputID = device.id; return }
        AudioDevices.setDefaultDevice(device.id, input: true)
        refreshAll()
    }

    func setMasterVolume(_ value: Float) {
        masterVolume = value
        guard !isPreview else { return }
        AudioDevices.setVolume(defaultOutputID, value)
        if masterMuted && value > 0 { toggleMasterMute() }
    }

    func toggleMasterMute() {
        if isPreview { masterMuted.toggle(); return }
        AudioDevices.setMuted(defaultOutputID, !masterMuted)
        masterMuted = AudioDevices.isMuted(defaultOutputID)
    }

    func setInputVolume(_ value: Float) {
        inputVolume = value
        guard !isPreview else { return }
        AudioDevices.setVolume(defaultInputID, value, input: true)
    }

    // MARK: Apps

    func refreshApps() {
        guard !isPreview else { return }
        let groups = AudioProcesses.groups()
        var entries: [AppEntry] = []
        for group in groups {
            if group.isPlaying { seenPlaying.insert(group.id) }
            let stored = settings[group.id] ?? AppSettings()
            let visible = group.isPlaying || seenPlaying.contains(group.id) || stored.needsTap
                || (showAllApps && group.isRegularApp)
            guard visible else { continue }
            entries.append(AppEntry(id: group.id, name: group.name, bundleID: group.bundleID,
                                    appPID: group.appPID, processObjectIDs: group.processObjectIDs,
                                    isPlaying: group.isPlaying, settings: stored, icon: icon(for: group),
                                    level: apps.first { $0.id == group.id }?.level ?? 0,
                                    error: tapErrors[group.id]))
        }
        // Feste, alphabetische Reihenfolge: Würde nach „spielt gerade“ sortiert, sprängen
        // Zeilen unter dem Mauszeiger weg, sobald eine App anfängt oder aufhört zu spielen.
        entries.sort { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        apps = entries
        icons = icons.filter { key, _ in groups.contains { $0.id == key } }
        syncTaps(groups: groups)
    }

    private func icon(for group: AudioAppGroup) -> NSImage {
        if let cached = icons[group.id] { return cached }
        var image: NSImage?
        if let app = NSRunningApplication(processIdentifier: group.appPID) { image = app.icon }
        if image == nil, let bundleID = group.bundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        }
        let result = image ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        icons[group.id] = result
        return result
    }

    private func syncTaps(groups: [AudioAppGroup]) {
        let byID = Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Taps beenden, deren App weg ist oder die wieder auf Standard steht.
        for key in Array(taps.keys) {
            guard byID[key] != nil else { removeTap(key); continue }
            let current = settings[key] ?? AppSettings()
            let settled = Date().timeIntervalSince(lastChange[key] ?? .distantPast) > 3
            if !current.needsTap && settled { removeTap(key) }
        }
        for group in groups {
            guard let current = settings[group.id], current.needsTap else { continue }
            ensureTap(for: group, settings: current)
        }
    }

    private func outputUID(for settings: AppSettings) -> String? {
        if let uid = settings.outputUID, outputs.contains(where: { $0.uid == uid }) { return uid }
        return AudioDevices.uid(of: defaultOutputID)
    }

    private func ensureTap(for group: AudioAppGroup, settings: AppSettings) {
        guard let uid = outputUID(for: settings) else { return }
        if let tap = taps[group.id] {
            if tap.outputUID != uid {
                removeTap(group.id)
            } else {
                do {
                    try tap.update(processObjectIDs: group.processObjectIDs)
                } catch {
                    removeTap(group.id) // beim nächsten Durchlauf neu aufbauen
                }
                return
            }
        }
        if permission != .granted { permission = AudioPermission.status }
        // Nur bei ausdrücklich verweigerter Erlaubnis nicht eingreifen (die App bliebe
        // sonst stumm). „Noch nicht entschieden“ meldet macOS bei ad-hoc signierten
        // Apps oft dauerhaft; dann einfach den Tap anlegen – macOS fragt dabei selbst.
        guard permission != .denied else { return }
        // Nach einem Fehler nicht bei jeder Reglerbewegung neu versuchen.
        if tapErrors[group.id] != nil,
           Date().timeIntervalSince(lastTapAttempt[group.id] ?? .distantPast) < 5 { return }
        lastTapAttempt[group.id] = Date()
        do {
            taps[group.id] = try AppTap(name: group.name, processObjectIDs: group.processObjectIDs,
                                        outputUID: uid, gain: settings.effectiveGain, eq: settings.eq)
            tapErrors[group.id] = nil
        } catch {
            tapErrors[group.id] = String(describing: error)
        }
        updateEntry(group.id) { $0.error = self.tapErrors[group.id] }
    }

    private func removeTap(_ key: String) {
        taps.removeValue(forKey: key)?.invalidate()
    }

    private func stopAllTaps() {
        for key in Array(taps.keys) { removeTap(key) }
    }

    private func updateLevels() {
        for index in apps.indices {
            let peak = taps[apps[index].id]?.processor.takePeak() ?? 0
            // Schnell hoch, langsam runter – wie eine echte Pegelanzeige.
            let falling = apps[index].level * 0.82
            let level = max(peak, falling < 0.01 ? 0 : falling)
            if level != apps[index].level { apps[index].level = level }
        }
    }

    private func updateEntry(_ id: String, _ change: (inout AppEntry) -> Void) {
        guard let index = apps.firstIndex(where: { $0.id == id }) else { return }
        change(&apps[index])
    }

    // MARK: Regler einer App

    func change(_ id: String, _ edit: (inout AppSettings) -> Void) {
        var value = settings[id] ?? AppSettings()
        let oldOutput = value.outputUID
        edit(&value)
        settings[id] = value
        lastChange[id] = Date()
        updateEntry(id) { $0.settings = value }
        guard !isPreview else { return }
        persist()

        if oldOutput != value.outputUID { removeTap(id) }
        if let tap = taps[id] {
            tap.processor.setGain(value.effectiveGain)
            tap.processor.setEQ(value.eq)
        } else if value.needsTap, let group = AudioProcesses.groups().first(where: { $0.id == id }) {
            ensureTap(for: group, settings: value)
        }
    }

    func setVolume(_ id: String, _ volume: Float) {
        change(id) {
            $0.volume = volume
            if volume > 0 { $0.muted = false }
        }
    }

    func toggleMute(_ id: String) { change(id) { $0.muted.toggle() } }
    func setOutput(_ id: String, _ uid: String?) { change(id) { $0.outputUID = uid } }
    func setEQ(_ id: String, _ eq: EQSettings) { change(id) { $0.eq = eq } }
    func reset(_ id: String) { change(id) { $0 = AppSettings() } }

    private func persist() {
        // Nur abweichende Einstellungen merken – und nur für echte Apps: Prozessnummern
        // werden nach einem Neustart neu vergeben und träfen sonst eine fremde App.
        let relevant = settings.filter { $0.value.needsTap && !$0.key.hasPrefix("pid:") }
        if let data = try? JSONEncoder().encode(relevant) { defaults.set(data, forKey: "appSettings") }
    }

    // MARK: Erlaubnis & Optionen

    /// Wurde die Erlaubnis in den Systemeinstellungen entzogen, alle Umleitungen
    /// abbauen – sonst blieben die betroffenen Apps stumm.
    private func checkPermission() {
        let current = AudioPermission.status
        if current == .denied && !taps.isEmpty { stopAllTaps() }
        if current != permission {
            permission = current
            if current == .granted { tapErrors.removeAll(); refreshApps() }
        }
    }

    func openPermissionSettings() {
        NSWorkspace.shared.open(AudioPermission.settingsURL)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            // Muss macOS erst zustimmen, gleich die passende Stelle öffnen statt nur zu piepen.
            if SMAppService.mainApp.status != .requiresApproval { NSSound.beep() }
        }
        refreshLaunchAtLogin()
        if enabled && launchAtLoginNeedsApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    func refreshLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        launchAtLoginNeedsApproval = status == .requiresApproval
    }

    func openSoundSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Text-Ausgabe für die Prüfung ohne Oberfläche (MISCHPULT_SELFTEST=1).
    static func selfTestReport() -> String {
        var lines = ["Ausgabe: \(AudioDevices.device(for: AudioDevices.defaultDevice())?.name ?? "?")"]
        lines.append("Ausgabegeräte: " + AudioDevices.outputs().map(\.name).joined(separator: ", "))
        lines.append("Eingabegeräte: " + AudioDevices.inputs().map(\.name).joined(separator: ", "))
        lines.append("Erlaubnis Systemaudio: \(AudioPermission.status)")
        for group in AudioProcesses.groups().sorted(by: { $0.name < $1.name }) {
            lines.append("App: \(group.name) [\(group.id)] Prozesse=\(group.processes.count)"
                         + (group.isPlaying ? " spielt" : "") + (group.isRegularApp ? "" : " (Hintergrund)"))
        }
        return lines.joined(separator: "\n")
    }
}
