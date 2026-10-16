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
            version: "1.4.2", date: "16.10.2026",
            de: [
                "Die App-Liste hat eine feste, alphabetische Reihenfolge – Zeilen springen nicht mehr weg, wenn eine App anfängt oder aufhört zu spielen.",
                "Bei vielen Apps ist die letzte sichtbare Zeile angeschnitten und der Scrollbalken sichtbar, damit man erkennt, dass es weitergeht.",
                "Verständliche Fehlermeldung statt Technik-Text (Details im Tooltip).",
                "Equalizer zeigt „0 dB“ statt „+0 dB“; Lautstärke-Symbole stehen bündig mit den Gerätekreisen.",
            ],
            en: [
                "The app list keeps a fixed, alphabetical order – rows no longer jump away when an app starts or stops playing.",
                "With many apps the last visible row is cut off and the scroll bar is shown, so you can tell there is more.",
                "Plain-language error message instead of technical text (details in the tooltip).",
                "Equalizer shows “0 dB” instead of “+0 dB”; volume symbols line up with the device circles.",
            ]),
        ChangelogEntry(
            version: "1.4.1", date: "16.10.2026",
            de: [
                "Die Optionen sind wieder direkt in der App: Das Zahnrad öffnet ein Aufklappmenü wie in Version 1.0.",
                "Der Regler „Glas-Intensität“ und das eigene Einstellungsfenster sind entfallen.",
            ],
            en: [
                "Options are back inside the app: the gear opens a drop-down menu like in version 1.0.",
                "The “Glass intensity” slider and the separate settings window have been removed.",
            ]),
        ChangelogEntry(
            version: "1.4.0", date: "16.10.2026",
            de: [
                "Neues, ruhiges Design im Stil des Ton-Menüs im Kontrollzentrum: Abschnitte mit kleinen Überschriften und feinen Trennlinien statt eigener Glaskacheln.",
                "Alle Aus- und Eingabegeräte stehen als Liste da – gewähltes Gerät mit blauem Kreis und Häkchen, Wechsel mit einem Klick.",
                "Ein Klick auf den App-Namen klappt Ausgabe und Equalizer auf.",
                "Beim Verstärken über 100 % färben sich Regler und Prozentzahl orange.",
                "Die Glas-Intensität regelt jetzt, wie stark der Hintergrund durch das ganze Fenster scheint.",
            ],
            en: [
                "New, calm design in the style of Control Center’s Sound menu: sections with small headings and fine dividers instead of custom glass tiles.",
                "All output and input devices are listed – the selected one has a blue circle and a checkmark, switch with one click.",
                "Clicking an app’s name expands output and equalizer.",
                "When boosting above 100 %, slider and percentage turn orange.",
                "Glass intensity now controls how much the background shows through the whole window.",
            ]),
        ChangelogEntry(
            version: "1.3.0", date: "16.10.2026",
            de: [
                "Wichtig: Die Lautstärke pro App wirkt wieder. Seit 1.1.0 wartete Mischpult auf eine Erlaubnis-Meldung, die macOS nie schickte.",
                "Einstellungen öffnen sich jetzt in einem eigenen Fenster (Zahnrad) – das Menüleisten-Fenster verrutscht und überlagert sich nicht mehr.",
                "Aus- und Eingabe zeigen wieder den Namen des Geräts.",
                "Glaskacheln verschmelzen nicht mehr zu einer großen Fläche; keine Glasknöpfe mehr auf Glas.",
                "„Erlaubnis Systemaudio …“ öffnet jetzt die richtige Seite der Systemeinstellungen.",
                "„Beim Anmelden starten“ führt zur Bestätigung in den Systemeinstellungen, wenn macOS sie verlangt.",
            ],
            en: [
                "Important: per-app volume works again. Since 1.1.0 Mischpult waited for a permission notice that macOS never sent.",
                "Settings now open in their own window (gear) – the menu bar window no longer shifts or overlaps.",
                "Output and input show the device name again.",
                "Glass tiles no longer merge into one large surface; no more glass buttons on glass.",
                "“System audio permission …” now opens the correct page in System Settings.",
                "“Open at login” leads to the approval in System Settings when macOS requires it.",
            ]),
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

enum ChangelogWindow {
    @MainActor
    static func show() {
        AuxWindow.show(id: "changelog", title: L("Versionsverlauf"), transparentTitlebar: true) {
            ChangelogView()
        }
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
