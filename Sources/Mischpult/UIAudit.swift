import AppKit
import CoreAudio
import MischpultCore
import SwiftUI

/// Prüfmodus für die Oberfläche: `MISCHPULT_UIAUDIT=<ordner>`.
///
/// Stellt das Menüleisten-Fenster mit Beispieldaten unsichtbar dar, spielt typische
/// Bedienschritte durch, misst die Fenstergröße nach jedem Schritt und legt je ein
/// Bild ab. Kein Zugriff auf Ton, Geräte oder gespeicherte Einstellungen.
@MainActor
enum UIAudit {
    static func run(into folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var report: [String] = []

        func icon(_ path: String) -> NSImage { NSWorkspace.shared.icon(forFile: path) }
        func app(_ id: String, _ name: String, _ path: String, playing: Bool = true, volume: Float = 1,
                 muted: Bool = false, output: String? = nil, eq: EQSettings = .flat,
                 level: Float = 0, error: String? = nil) -> AppEntry {
            var settings = AppSettings()
            settings.volume = volume
            settings.muted = muted
            settings.outputUID = output
            settings.eq = eq
            return AppEntry(id: id, name: name, bundleID: id, appPID: 0, processObjectIDs: [],
                            isPlaying: playing, settings: settings, icon: icon(path), level: level, error: error)
        }
        let speakers = AudioDevice(id: 1, uid: "speakers", name: "MacBook Air-Lautsprecher",
                                   hasOutput: true, hasInput: false, transportType: kAudioDeviceTransportTypeBuiltIn)
        let airpods = AudioDevice(id: 2, uid: "airpods", name: "AirPods Max von Marc",
                                  hasOutput: true, hasInput: true, transportType: kAudioDeviceTransportTypeBluetooth)
        let mic = AudioDevice(id: 3, uid: "mic", name: "MacBook Air-Mikrofon",
                              hasOutput: false, hasInput: true, transportType: kAudioDeviceTransportTypeBuiltIn)
        let iphone = AudioDevice(id: 4, uid: "iphone", name: "Mikrofon von „Trollwelt 2“",
                                 hasOutput: false, hasInput: true, transportType: kAudioDeviceTransportTypeContinuityCaptureWireless)

        let base = [
            app("com.apple.Safari", "Safari", "/Applications/Safari.app", volume: 0.47, level: 0.35),
            app("com.apple.Music", "Musik", "/System/Applications/Music.app", level: 0.7),
            app("com.hnc.Discord", "Discord", "/Applications/Discord.app", volume: 1.4, output: "airpods",
                eq: EQSettings(bass: 4), level: 0.9),
            app("com.apple.mail", "Mail", "/System/Applications/Mail.app", playing: false, muted: true),
        ]
        let store = MixerStore(preview: base, outputs: [speakers, airpods], inputs: [mic, iphone])

        let host = NSHostingView(rootView: AnyView(MixerView().environmentObject(store)))
        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.state = .active
        effect.blendingMode = .behindWindow
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 340, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = effect
        effect.addSubview(host)

        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.35)) }

        func capture(_ name: String, dark: Bool = true) {
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            settle()
            let size = host.fittingSize
            window.setContentSize(size)
            effect.frame = NSRect(origin: .zero, size: size)
            host.frame = effect.bounds
            host.layoutSubtreeIfNeeded()
            settle()
            report.append(String(format: "%-28@ %4.0f × %4.0f", name as NSString, size.width, size.height))
            guard let rep = effect.bitmapImageRepForCachingDisplay(in: effect.bounds) else { return }
            effect.cacheDisplay(in: effect.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: folder.appendingPathComponent(name + ".png"))
        }

        capture("01-start-dunkel")
        capture("02-start-hell", dark: false)
        store.expandedApp = "com.hnc.Discord"
        capture("03-discord-aufgeklappt")
        store.expandedApp = nil
        capture("04-wieder-zugeklappt")
        store.toggleMute("com.apple.Music")
        capture("05-musik-stumm")
        store.toggleMute("com.apple.Music")
        store.setVolume("com.apple.Safari", 2)
        capture("06-safari-200-prozent")
        store.selectOutput(airpods)
        capture("07-ausgabe-airpods")
        store.toggleMasterMute()
        capture("08-gesamt-stumm")
        store.toggleMasterMute()
        store.previewSet(permission: .denied)
        capture("09-erlaubnis-fehlt")
        store.previewSet(apps: [], permission: .granted)
        capture("10-keine-apps")
        let many = (1...9).map { index in
            app("app\(index)", index == 1 ? "Eine App mit einem wirklich sehr langen Namen" : "App \(index)",
                "/System/Applications/Notes.app", playing: index % 2 == 0, level: Float(index) / 10)
        }
        store.previewSet(apps: many)
        capture("11-neun-apps-scrollen")
        store.previewSet(apps: [app("com.apple.Safari", "Safari", "/Applications/Safari.app",
                                    error: "Tap anlegen fehlgeschlagen (-1)")])
        capture("12-fehlermeldung")

        try? report.joined(separator: "\n").write(to: folder.appendingPathComponent("bericht.txt"),
                                                   atomically: true, encoding: .utf8)
        print(report.joined(separator: "\n"))
    }
}
