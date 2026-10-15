import AppKit
import SwiftUI

/// Ein Eintrag im Versionsverlauf (Deutsch und Englisch).
struct ChangelogEntry: Identifiable {
    let version: String
    let date: String
    let de: [String]
    let en: [String]
    var id: String { version }

    var items: [String] {
        Bundle.main.preferredLocalizations.first == "de" ? de : en
    }
}

/// Bei jedem Release oben ergänzen – gleiche Punkte wie in CHANGELOG.md.
enum Changelog {
    static let entries: [ChangelogEntry] = [
        ChangelogEntry(
            version: "1.1.0", date: "15.10.2026",
            de: [
                "Neues Design im Liquid-Glass-Stil von macOS: Glas-Kacheln und große Regler wie im Kontrollzentrum.",
                "Versionsverlauf direkt in der App (Menü „…“ → Versionsverlauf).",
                "Mischpult fragt jetzt zuerst nach der Erlaubnis „Systemaudio“ – Apps werden während des Dialogs nicht mehr stumm.",
                "Wird die Erlaubnis entzogen, gibt Mischpult alle Apps sofort wieder frei.",
                "Behebt einen möglichen Absturz beim Erlaubnisdialog.",
                "Equalizer-Änderungen können keine Störgeräusche mehr verursachen; ein hängender Filter setzt sich selbst zurück.",
                "Bei 100 % bleibt der Ton völlig unverändert, der Begrenzer greift nur noch beim Verstärken.",
                "Der Equalizer passt sich an, wenn ein Gerät die Abtastrate wechselt.",
                "Mono-Lautsprecher geben jetzt beide Stereokanäle wieder.",
                "Ton läuft direkt auf dem Echtzeit-Thread von Core Audio: weniger Verzögerung, weniger Aussetzer.",
                "Weniger Rechenlast bei geöffnetem Fenster.",
            ],
            en: [
                "New design in the macOS Liquid Glass style: glass tiles and large sliders like Control Center.",
                "Version history right inside the app (“…” menu → Version History).",
                "Mischpult now asks for the “System Audio” permission first – apps no longer go silent while the dialog is open.",
                "If the permission is revoked, Mischpult releases all apps immediately.",
                "Fixes a possible crash in the permission dialog.",
                "Equalizer changes can no longer cause noise; a stuck filter resets itself.",
                "At 100 % the sound stays completely untouched; the limiter only kicks in when boosting.",
                "The equalizer adapts when a device changes its sample rate.",
                "Mono speakers now play both stereo channels.",
                "Audio runs directly on Core Audio’s real-time thread: lower latency, fewer dropouts.",
                "Less CPU usage while the window is open.",
            ]),
        ChangelogEntry(
            version: "1.0.0", date: "15.10.2026",
            de: [
                "Erste Version.",
                "Lautstärke pro App von 0 bis 200 %, Stummschalten per Klick auf das App-Symbol.",
                "Eigenes Ausgabegerät und 3-Band-Equalizer pro App.",
                "Pegelanzeige, Geräteauswahl, Gesamtlautstärke und Mikrofonpegel.",
            ],
            en: [
                "First release.",
                "Per-app volume from 0 to 200 %, mute with a click on the app icon.",
                "Per-app output device and 3-band equalizer.",
                "Level meter, device selection, master volume and microphone level.",
            ]),
    ]
}

/// Eigenes AppKit-Fenster: Eine SwiftUI-`Window`-Szene würde sich bei einer
/// reinen Menüleisten-App unter macOS 14 schon beim Start öffnen.
@MainActor
enum ChangelogWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let created = NSWindow(contentViewController: NSHostingController(rootView: ChangelogView()))
            created.title = L("Versionsverlauf")
            created.styleMask = [.titled, .closable, .fullSizeContentView]
            created.titlebarAppearsTransparent = true
            created.titleVisibility = .hidden
            created.isMovableByWindowBackground = true
            created.isReleasedWhenClosed = false
            created.center()
            window = created
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct ChangelogView: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Versionsverlauf")
                            .font(.title2.weight(.semibold))
                        Text("Mischpult – ein Hobbyprojekt")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 4)
                GlassGroup(spacing: 14) {
                    VStack(spacing: 12) {
                        ForEach(Changelog.entries) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(String(format: L("Version %@"), entry.version))
                                        .font(.headline)
                                    if entry.id == Changelog.entries.first?.id {
                                        Text("Aktuell")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2)
                                            .foregroundStyle(.white)
                                            .background(Capsule().fill(Color.accentColor))
                                    }
                                    Spacer()
                                    Text(entry.date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(entry.items, id: \.self) { item in
                                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                                        Circle()
                                            .fill(Color.accentColor)
                                            .frame(width: 5, height: 5)
                                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                                        Text(item)
                                            .font(.callout)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassTile(cornerRadius: 18)
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 460, height: 520)
    }
}
