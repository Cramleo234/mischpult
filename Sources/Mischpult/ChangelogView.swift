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
            version: "1.2.3", date: "15.10.2026",
            de: [
                "Behebt, dass Einstellungen und Regler gleichzeitig übereinander angezeigt wurden.",
            ],
            en: [
                "Fixes Settings and the sliders being shown on top of each other at the same time.",
            ]),
        ChangelogEntry(
            version: "1.2.2", date: "15.10.2026",
            de: [
                "Das Fenster bleibt jetzt an der Menüleiste, wenn man die Einstellungen (Zahnrad) öffnet oder eine App aufklappt.",
            ],
            en: [
                "The window now stays attached to the menu bar when opening Settings (gear) or expanding an app.",
            ]),
        ChangelogEntry(
            version: "1.2.1", date: "15.10.2026",
            de: [
                "Behebt ein leeres oder abgeschnittenes Fenster beim ersten Öffnen.",
                "Die Regler sehen wieder aus wie in Version 1.0: normale macOS-Schieberegler, darunter gut sichtbar der Pegel jeder App.",
            ],
            en: [
                "Fixes an empty or cut-off window when opening it for the first time.",
                "Sliders look like in version 1.0 again: standard macOS sliders with each app’s level clearly visible below.",
            ]),
        ChangelogEntry(
            version: "1.2.0", date: "15.10.2026",
            de: [
                "Neuer Regler „Glas-Intensität“ in den Einstellungen: von vollem Liquid Glass bis zu ruhigen, deckenden Flächen.",
                "Die Optionen sind jetzt ein Einstellungsfeld (Zahnrad oben rechts) statt eines Menüs.",
                "Der Versionsverlauf scrollt jetzt flüssig.",
            ],
            en: [
                "New “Glass intensity” slider in Settings: from full Liquid Glass to calm, opaque surfaces.",
                "Options are now a settings panel (gear at the top right) instead of a menu.",
                "The version history now scrolls smoothly.",
            ]),
        ChangelogEntry(
            version: "1.1.0", date: "15.10.2026",
            de: [
                "Neues Design im Liquid-Glass-Stil von macOS: Glas-Kacheln und große Regler wie im Kontrollzentrum.",
                "Versionsverlauf direkt in der App.",
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
                "Version history right inside the app.",
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

/// Bewusst ohne Glas-Effekte: Viele Glasflächen in einer Scroll-Ansicht müssen
/// bei jedem Bild neu berechnet werden und lassen das Scrollen ruckeln.
struct ChangelogView: View {

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
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
                .padding(.bottom, 6)
                ForEach(Changelog.entries) { entry in
                    EntryCard(entry: entry, isCurrent: entry.id == Changelog.entries.first?.id)
                }
            }
            .padding(20)
            .padding(.top, 14)
        }
        .frame(width: 460, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct EntryCard: View {
    let entry: ChangelogEntry
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: L("Version %@"), entry.version))
                    .font(.headline)
                if isCurrent {
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
                    Text(verbatim: "•").foregroundStyle(Color.accentColor)
                    Text(item)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.07)))
    }
}
