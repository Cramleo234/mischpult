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
    /// Lautstärke der Mitteilungs- und Hinweistöne (0 … 1); nil = nicht lesbar.
    @Published private(set) var alertVolume: Float?
    @Published private(set) var inputHasVolume = false
    @Published private(set) var permission = AudioPermission.status
    @Published var expandedApp: String?
    @Published var showAllApps: Bool {
        didSet {
            guard !isPreview else { return }
            defaults.set(showAllApps, forKey: "showAllApps")
            refreshApps(force: true)
        }
    }
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// Bluetooth-Kopfhörer im Telefon-Modus (nur bei geschlossenem Fenster aktualisiert,
    /// damit sich die Fensterhöhe beim Bedienen nicht ändert).
    @Published private(set) var callMode: CallModeStatus?
    private var notifiedCallMode: CallModeStatus?
    /// Verhindert den Telefon-Modus von Bluetooth-Kopfhörern: Wird ein Bluetooth-
    /// Mikrofon zum Standard-Eingang, schaltet Mischpult auf das eingebaute zurück.
    @Published var keepBluetoothQuality: Bool {
        didSet {
            guard !isPreview else { return }
            defaults.set(keepBluetoothQuality, forKey: "keepBluetoothQuality")
            if keepBluetoothQuality { avoidBluetoothInput() }
        }
    }
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
    private var visibleSince = Date.distantPast
    /// App-Symbole einmal laden statt bei jedem Neuzeichnen (20 × pro Sekunde).
    private var icons: [String: NSImage] = [:]
    private var lastTapAttempt: [String: Date] = [:]
    /// Ausgabegeräte, auf denen der getrennte Bluetooth-Weg keinen Ton geliefert hat.
    private var splitUnsupported: Set<String> = []
    /// Prüfmodus (MISCHPULT_UIAUDIT): nur Beispieldaten, kein Zugriff auf Ton oder Geräte.
    let isPreview: Bool

    /// Steuerung mit Beispieldaten für den Prüfmodus.
    init(preview apps: [AppEntry], outputs: [AudioDevice], inputs: [AudioDevice]) {
        isPreview = true
        showAllApps = false
        keepBluetoothQuality = true
        self.apps = apps
        self.outputs = outputs
        self.inputs = inputs
        defaultOutputID = outputs.first?.id ?? 0
        defaultInputID = inputs.first?.id ?? 0
        masterVolume = 0.56
        masterHasVolume = true
        inputVolume = 0.64
        inputHasVolume = true
        alertVolume = 0.3
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
        keepBluetoothQuality = defaults.object(forKey: "keepBluetoothQuality") as? Bool ?? true
        if let data = defaults.data(forKey: "appSettings"),
           let stored = try? JSONDecoder().decode([String: AppSettings].self, from: data) {
            settings = stored
        }
        let system = AudioObjectID(kAudioObjectSystemObject)
        // Meldungen kommen oft in Schüben; mehrere kurz hintereinander lösen nur einen
        // einzigen Neuaufbau aus. Prozess-Änderungen betreffen nur die App-Liste.
        if let listener = CAListener(object: system, address: CAProperty.address(kAudioHardwarePropertyProcessObjectList),
                                     handler: { [weak self] in self?.scheduleRefresh(devices: false) }) {
            listeners.append(listener)
        }
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice,
                         kAudioHardwarePropertyDefaultInputDevice] {
            if let listener = CAListener(object: system, address: CAProperty.address(selector),
                                         handler: { [weak self] in self?.scheduleRefresh(devices: true) }) {
                listeners.append(listener)
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopAllTaps() }
        }
        CallModeNotifier.shared.setUp(store: self)
        refreshAll()
        refreshAlertVolume()
        scheduleTimer()
    }

    private var pendingRefresh: (devices: Bool, scheduled: Bool) = (false, false)

    /// Bündelt Core-Audio-Meldungen: höchstens ein Neuaufbau pro halbe Sekunde.
    private func scheduleRefresh(devices: Bool) {
        pendingRefresh.devices = pendingRefresh.devices || devices
        guard !pendingRefresh.scheduled else { return }
        pendingRefresh.scheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let withDevices = self.pendingRefresh.devices
                self.pendingRefresh = (false, false)
                if withDevices { self.refreshDevices() }
                self.refreshApps()
            }
        }
    }

    // MARK: Sichtbarkeit / Takt

    func setVisible(_ visible: Bool) {
        guard !isPreview, visible != isVisible else { return }
        isVisible = visible
        if visible { visibleSince = Date() }
        if visible {
            // Beim Öffnen keine Listen neu aufbauen: Das Fenster ist schon gezeichnet,
            // eine andere Höhe würde es verschieben. Aktuell gehalten wird die Liste,
            // solange das Fenster zu ist (Zeitgeber und Core-Audio-Meldungen).
            checkPermission()
            refreshLaunchAtLogin()
            refreshVolumes()
            refreshAlertVolume()
        } else {
            expandedApp = nil
            refreshAll()
        }
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        // Stromsparend: Geschlossen nur alle 5 s nachsehen (neue Apps melden sich
        // ohnehin per Core-Audio-Meldung). Offen 20 × pro Sekunde nur, wenn eine
        // umgeleitete App einen Pegel liefert – sonst einmal pro Sekunde.
        let fast = isVisible && !taps.isEmpty
        let interval: TimeInterval = isVisible ? (fast ? 1.0 / 20 : 1) : 5
        let ticksPerSecond = Int((1 / interval).rounded())
        var ticks = 0
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                ticks += 1
                if self.isVisible {
                    if fast { self.updateLevels() }
                    if ticks % max(ticksPerSecond, 1) == 0 { self.refreshApps(); self.refreshVolumes() }
                    if ticks % (20 * max(ticksPerSecond, 1)) == 0 { self.checkPermission() }
                    // Taps kamen hinzu oder fielen weg: Takt anpassen.
                    if fast != !self.taps.isEmpty { self.scheduleTimer() }
                } else {
                    self.refreshApps()
                    if ticks % 6 == 0 { self.checkPermission() }
                }
            }
        }
        timer?.tolerance = interval * 0.2
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
        avoidBluetoothInput()
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

    /// Mitteilungs-Lautstärke lesen. Nur beim Start und beim Öffnen des Fensters:
    /// Jeder Lesevorgang startet einen kleinen Hilfsprozess, und der meldet sich bei
    /// Core Audio an – würde das bei jeder Prozess-Meldung passieren, entstünde eine
    /// Endlosschleife (so geschehen in 1.5.0–1.6.0, ca. 25 % Dauerlast).
    private func refreshAlertVolume() {
        AlertVolume.get { [weak self] value in
            MainActor.assumeIsolated {
                guard let self, Date().timeIntervalSince(self.lastAlertChange) > 1.5 else { return }
                self.alertVolume = value
            }
        }
    }

    // MARK: Mitteilungstöne

    private static let alertVolumeBeforeMuteKey = "alertVolumeBeforeMute"
    private var lastAlertChange = Date.distantPast

    func setAlertVolume(_ value: Float) {
        let changed = AlertVolume.scriptValue(value) != AlertVolume.scriptValue(alertVolume ?? -1)
        alertVolume = value
        lastAlertChange = Date()
        // Beim Ziehen nur dann an macOS schicken, wenn sich der ganze Prozentwert ändert.
        if changed && !isPreview { AlertVolume.set(value) }
    }

    /// Stumm schalten merkt sich den vorherigen Wert; erneutes Klicken stellt ihn wieder her.
    func toggleAlertMute() {
        guard let current = alertVolume else { return }
        if current > 0.001 {
            defaults.set(current, forKey: Self.alertVolumeBeforeMuteKey)
            setAlertVolume(0)
        } else {
            let previous = defaults.object(forKey: Self.alertVolumeBeforeMuteKey) as? Float ?? 0.5
            setAlertVolume(previous > 0.001 ? previous : 0.5)
        }
    }

    // MARK: Telefon-Modus

    private func updateCallMode(groups: [AudioAppGroup], force: Bool) {
        let status = BluetoothCallMode.detect(groups: groups, devices: inputs, defaultInputID: defaultInputID)
        // Hinweis im Fenster nur ändern, solange es zu ist (sonst verrutscht es).
        if !isVisible || force { callMode = status }
        if let status, status != notifiedCallMode {
            CallModeNotifier.shared.notify(status)
        } else if status == nil, notifiedCallMode != nil {
            CallModeNotifier.shared.clear()
        }
        notifiedCallMode = status
    }

    /// „Telefon-Modus beenden“: Standard-Eingang weg vom Bluetooth-Mikrofon.
    func fixCallMode() {
        guard !isPreview, let replacement = AudioDevices.inputAvoidingBluetooth(inputs) else { return }
        AudioDevices.setDefaultDevice(replacement.id, input: true)
        defaultInputID = AudioDevices.defaultDevice(input: true)
        CallModeNotifier.shared.clear()
        // Apps brauchen einen Moment, um auf den neuen Eingang zu wechseln.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            MainActor.assumeIsolated { self?.refreshApps(force: true) }
        }
    }

    /// Nur für den Prüfmodus.
    func previewSetCallMode(_ status: CallModeStatus?) {
        guard isPreview else { return }
        callMode = status
    }

    /// Ist ein Bluetooth-Mikrofon Standard-Eingang geworden (macOS macht das beim
    /// Verbinden von Kopfhörern oft selbst), auf einen anderen Eingang wechseln.
    private func avoidBluetoothInput() {
        guard keepBluetoothQuality, !isPreview,
              let current = inputs.first(where: { $0.id == defaultInputID }), current.isBluetooth,
              let replacement = AudioDevices.inputAvoidingBluetooth(inputs) else { return }
        AudioDevices.setDefaultDevice(replacement.id, input: true)
        defaultInputID = AudioDevices.defaultDevice(input: true)
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
        // Bewusst ein Bluetooth-Mikrofon gewählt: Der Wunsch gilt, der Schutz geht aus.
        if device.isBluetooth && keepBluetoothQuality { keepBluetoothQuality = false }
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

    /// Solange das Fenster offen ist, bleiben die Zeilen fest (nur Werte werden
    /// aktualisiert): Jede neue oder verschwundene Zeile änderte die Fensterhöhe,
    /// und macOS verschiebt das Menüleisten-Fenster dabei. Neue Apps erscheinen
    /// beim nächsten Öffnen. `force` nur nach einer bewussten Nutzeraktion.
    func refreshApps(force: Bool = false) {
        guard !isPreview else { return }
        let groups = AudioProcesses.groups()
        updateCallMode(groups: groups, force: force)
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
        // Sicherheitsnetz: Bleibt die Meldung „Fenster zu“ aus irgendeinem Grund aus,
        // darf die Liste trotzdem nicht ewig eingefroren bleiben.
        let freezeList = isVisible && Date().timeIntervalSince(visibleSince) < 120
        if freezeList && !force {
            let fresh = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            apps = apps.map { row in
                guard var updated = fresh[row.id] else {
                    var stopped = row
                    stopped.isPlaying = false
                    return stopped
                }
                updated.level = row.level
                return updated
            }
        } else {
            apps = entries
        }
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
            // Kontrolle des Bluetooth-Wegs: Spielt die App, kommt aber nach drei Sekunden
            // kein Ton an, auf diesem Gerät dauerhaft den bewährten Weg benutzen.
            let silentSplit = tap.mode == .split && group.isPlaying && !tap.hasDeliveredAudio
                && Date().timeIntervalSince(tap.createdAt) > 3
            if silentSplit { splitUnsupported.insert(uid) }
            if tap.outputUID != uid || silentSplit {
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
                                        outputUID: uid, gain: settings.effectiveGain, eq: settings.eq,
                                        allowSplit: !splitUnsupported.contains(uid))
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
        let inputs = AudioDevices.inputs()
        let defaultInput = AudioDevices.defaultDevice(input: true)
        if let input = inputs.first(where: { $0.id == defaultInput }) {
            lines.append("Eingang: \(input.name)" + (input.isBluetooth ? " (Bluetooth!)" : ""))
        }
        if let call = BluetoothCallMode.detect(groups: AudioProcesses.groups(), devices: inputs,
                                               defaultInputID: defaultInput) {
            lines.append("Telefon-Modus: \(call.deviceName) durch \(call.appNames.joined(separator: ", "))")
        } else {
            lines.append("Telefon-Modus: nein")
        }
        lines.append("Mitteilungstöne: " + (AlertVolume.readNow().map { "\(AlertVolume.scriptValue($0)) %" } ?? "nicht lesbar"))
        for group in AudioProcesses.groups().sorted(by: { $0.name < $1.name }) {
            lines.append("App: \(group.name) [\(group.id)] Prozesse=\(group.processes.count)"
                         + (group.isPlaying ? " spielt" : "") + (group.isRegularApp ? "" : " (Hintergrund)"))
        }
        return lines.joined(separator: "\n")
    }
}
