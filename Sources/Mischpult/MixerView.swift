import CoreAudio
import MischpultCore
import SwiftUI

// Aufbau wie das Ton-Menü im Kontrollzentrum: Das Menüleisten-Fenster ist selbst
// schon eine Glasfläche; darauf liegen nur Abschnitte mit kleinen Überschriften
// und feinen Trennlinien. Keine eigenen Glaskacheln, kein Inhaltstausch (Einstellungen
// sind ein Aufklappmenü, das als eigenes Popup erscheint) und keine animierten Höhenänderungen – sonst verrutscht
// das Fenster.

/// Das Fenster unter dem Menüleisten-Symbol.
struct MixerView: View {
    @EnvironmentObject private var store: MixerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header()
            if store.permission == .denied {
                PermissionBanner()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
            OutputSection()
            SectionDivider()
            AppsSection()
            SectionDivider()
            InputSection()
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(width: 340)
        .onAppear { store.setVisible(true) }
        .onDisappear { store.setVisible(false) }
    }
}

// MARK: Bausteine

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 4)
    }
}

private struct SectionDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
    }
}

/// Zeilen-Hintergrund beim Überfahren, wie bei Menüeinträgen.
private struct HoverHighlight: ViewModifier {
    var cornerRadius: CGFloat = 6
    var selected = false
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(selected ? 0.08 : (hovering ? 0.06 : 0))))
            .onHover { hovering = $0 }
    }
}

/// Lautstärkezeile: Symbol, Regler, Prozent.
private struct LevelRow: View {
    let symbol: String
    let value: Float
    var enabled = true
    var symbolHelp: String? = nil
    var onSymbolTap: (() -> Void)? = nil
    let onChange: (Float) -> Void
    let accessibilityLabel: Text

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let onSymbolTap {
                    Button(action: onSymbolTap) {
                        Image(systemName: symbol).frame(width: 20)
                    }
                    .buttonStyle(.borderless)
                } else {
                    Image(systemName: symbol).frame(width: 20)
                }
            }
            .foregroundStyle(.secondary)
            .help(symbolHelp ?? "")
            Slider(value: Binding(get: { value }, set: onChange), in: 0...1)
                .controlSize(.small)
                .disabled(!enabled)
                .accessibilityLabel(accessibilityLabel)
            Text(enabled ? percent(value) : "–")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
    }
}

/// Ein Gerät als Zeile: farbiger Kreis, Name, Häkchen – wie im Ton-Menü von macOS.
private struct DeviceRow: View {
    let device: AudioDevice
    let selected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: device.symbolName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.7))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(selected ? Color.accentColor : Color.primary.opacity(0.1)))
                Text(device.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(HoverHighlight())
        .padding(.horizontal, 6)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Kopfzeile

private struct Header: View {
    @EnvironmentObject private var store: MixerStore

    var body: some View {
        HStack {
            Text("Mischpult")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            OptionsMenu()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }
}

/// Optionen wie in Version 1.0: ein normales macOS-Aufklappmenü. Es erscheint als
/// eigenes Popup und verändert das Menüleisten-Fenster nicht.
private struct OptionsMenu: View {
    @EnvironmentObject private var store: MixerStore

    var body: some View {
        Menu {
            Toggle("Alle Apps anzeigen", isOn: $store.showAllApps)
            Toggle("Beim Anmelden starten", isOn: Binding(get: { store.launchAtLogin },
                                                          set: { store.setLaunchAtLogin($0) }))
            Divider()
            Button("Ton-Einstellungen öffnen …") { store.openSoundSettings() }
            Button("Erlaubnis Systemaudio …") { store.openPermissionSettings() }
            Button("Versionsverlauf …") { ChangelogWindow.show() }
            Divider()
            Text(String(format: L("Mischpult %@ – ein Hobbyprojekt"), version))
            Button("Mischpult beenden") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("Optionen"))
        .accessibilityLabel(Text("Optionen"))
        .onAppear { store.refreshLaunchAtLogin() }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }
}

// MARK: Hinweis zur Erlaubnis

private struct PermissionBanner: View {
    @EnvironmentObject private var store: MixerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Zugriff auf Systemaudio fehlt", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
            Text("Mischpult braucht die Erlaubnis „Nur Systemaudio aufnehmen“, um die Lautstärke einzelner Apps zu regeln.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Systemeinstellungen öffnen") { store.openPermissionSettings() }
                .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.orange.opacity(0.12)))
    }
}

// MARK: Ausgabe

private struct OutputSection: View {
    @EnvironmentObject private var store: MixerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader(title: L("Ausgabe"))
            LevelRow(symbol: speakerSymbol(store.masterMuted ? 0 : store.masterVolume),
                     value: store.masterVolume, enabled: store.masterHasVolume,
                     symbolHelp: store.masterMuted ? L("Ton einschalten") : L("Stummschalten"),
                     onSymbolTap: { store.toggleMasterMute() },
                     onChange: { store.setMasterVolume($0) },
                     accessibilityLabel: Text("Gesamtlautstärke"))
            ForEach(store.outputs) { device in
                DeviceRow(device: device, selected: device.id == store.defaultOutputID) {
                    store.selectOutput(device)
                }
            }
        }
    }
}

// MARK: Eingabe

private struct InputSection: View {
    @EnvironmentObject private var store: MixerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader(title: L("Eingabe"))
            if store.inputHasVolume {
                LevelRow(symbol: "mic", value: store.inputVolume,
                         onChange: { store.setInputVolume($0) },
                         accessibilityLabel: Text("Mikrofonpegel"))
            }
            ForEach(store.inputs) { device in
                DeviceRow(device: device, selected: device.id == store.defaultInputID) {
                    store.selectInput(device)
                }
            }
        }
    }
}

// MARK: Apps

private struct AppsSection: View {
    @EnvironmentObject private var store: MixerStore
    static let maxRowsWithoutScrolling = 6

    private var title: String {
        let playing = store.apps.filter(\.isPlaying).count
        switch playing {
        case 0: return L("Apps")
        case 1: return L("Apps · 1 spielt Ton")
        default: return String(format: L("Apps · %d spielen Ton"), playing)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionHeader(title: title)
                .help(L("Unveränderte Apps laufen direkt zum Gerät."))
            if store.apps.isEmpty {
                Text("Gerade spielt keine App Ton ab.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            } else if store.apps.count <= Self.maxRowsWithoutScrolling {
                // Ohne Scroll-Ansicht: Sie könnte beim Öffnen auf null schrumpfen.
                rows
            } else {
                ScrollView { rows }
                    .frame(height: 360)
            }
        }
    }

    private var rows: some View {
        VStack(spacing: 2) {
            ForEach(store.apps) { app in
                AppRow(app: app)
            }
        }
    }
}

private struct AppRow: View {
    @EnvironmentObject private var store: MixerStore
    let app: AppEntry

    private var expanded: Bool { store.expandedApp == app.id }
    private var boosted: Bool { app.settings.volume > 1.005 && !app.settings.muted }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Button { store.toggleMute(app.id) } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Image(nsImage: app.icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 28, height: 28)
                            .saturation(app.settings.muted ? 0 : 1)
                            .opacity(app.settings.muted ? 0.45 : 1)
                        if app.settings.muted {
                            Image(systemName: "speaker.slash.circle.fill")
                                .font(.system(size: 12))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .red)
                                .offset(x: 3, y: 3)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(app.settings.muted ? L("Ton einschalten") : L("Stummschalten"))
                .accessibilityLabel(app.settings.muted
                                    ? Text("\(app.name): Ton einschalten") : Text("\(app.name): Stummschalten"))

                VStack(alignment: .leading, spacing: 1) {
                    // Klick auf die Namenszeile klappt Ausgabe und Equalizer auf.
                    HStack(spacing: 5) {
                        Text(app.name)
                            .font(.system(size: 13))
                            .lineLimit(1)
                        badges
                        Spacer(minLength: 4)
                        Text(app.settings.muted ? L("Stumm") : percent(app.settings.volume))
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(boosted ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 12)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { store.expandedApp = expanded ? nil : app.id }
                    .help(L("Ausgabe und Equalizer"))
                    .accessibilityAddTraits(.isButton)

                    VolumeSlider(value: Binding(get: { app.settings.volume },
                                                set: { store.setVolume(app.id, $0) }),
                                 level: app.level, muted: app.settings.muted)
                        .accessibilityLabel(Text("Lautstärke \(app.name)"))
                }
            }
            if let error = app.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(.leading, 38)
                    .padding(.top, 4)
            }
            if expanded {
                AppDetails(app: app)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .modifier(HoverHighlight(cornerRadius: 8, selected: expanded))
        .padding(.horizontal, 6)
    }

    @ViewBuilder private var badges: some View {
        if let uid = app.settings.outputUID, let device = store.outputs.first(where: { $0.uid == uid }) {
            Image(systemName: device.symbolName)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .help(device.name)
        }
        if !app.settings.eq.isFlat {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .help(L("Equalizer aktiv"))
        }
    }
}

/// Lautstärkeregler 0–200 % mit Pegelanzeige darunter (wie in Version 1.0).
private struct VolumeSlider: View {
    @Binding var value: Float
    let level: Float
    let muted: Bool

    var body: some View {
        VStack(spacing: 2) {
            Slider(value: Binding(get: { Double(value) }, set: { newValue in
                // Bei 100 % leicht einrasten, damit man den Normalwert sicher trifft.
                value = abs(newValue - 1) < 0.04 ? 1 : Float(newValue)
            }), in: 0...Double(AppSettings.volumeRange.upperBound))
            .controlSize(.small)
            .tint(value > 1.005 && !muted ? .orange : nil)
            .opacity(muted ? 0.5 : 1)
            LevelBar(level: level)
                .padding(.horizontal, 2)
        }
    }
}

private struct AppDetails: View {
    @EnvironmentObject private var store: MixerStore
    let app: AppEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.bottom, 2)
            HStack(spacing: 8) {
                Text("Ausgabe")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 46, alignment: .leading)
                Picker("Ausgabe", selection: Binding(get: { app.settings.outputUID ?? "" },
                                                     set: { store.setOutput(app.id, $0.isEmpty ? nil : $0) })) {
                    Text("Systemausgabe").tag("")
                    if let uid = app.settings.outputUID, !store.outputs.contains(where: { $0.uid == uid }) {
                        Text("Gerät nicht verbunden").tag(uid)
                    }
                    Divider()
                    ForEach(store.outputs) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
                Spacer()
            }
            EQRow(title: "Bässe", value: app.settings.eq.bass) { value in
                var eq = app.settings.eq; eq.bass = value; store.setEQ(app.id, eq)
            }
            EQRow(title: "Mitten", value: app.settings.eq.mid) { value in
                var eq = app.settings.eq; eq.mid = value; store.setEQ(app.id, eq)
            }
            EQRow(title: "Höhen", value: app.settings.eq.treble) { value in
                var eq = app.settings.eq; eq.treble = value; store.setEQ(app.id, eq)
            }
            HStack {
                Spacer()
                Button("Zurücksetzen") { store.reset(app.id) }
                    .controlSize(.small)
                    .disabled(!app.settings.needsTap)
            }
        }
        .padding(.leading, 38)
        .padding(.top, 8)
    }
}

private struct EQRow: View {
    let title: LocalizedStringKey
    let value: Float
    let onChange: (Float) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)
            Slider(value: Binding(get: { Double(value) }, set: { newValue in
                onChange(abs(newValue) < 0.6 ? 0 : Float(newValue.rounded()))
            }), in: Double(EQSettings.range.lowerBound)...Double(EQSettings.range.upperBound))
            .controlSize(.mini)
            .accessibilityLabel(Text(title))
            Text(String(format: "%+.0f dB", value))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

func speakerSymbol(_ volume: Float) -> String {
    switch volume {
    case ..<0.001: return "speaker.slash.fill"
    case ..<0.34: return "speaker.wave.1.fill"
    case ..<0.67: return "speaker.wave.2.fill"
    default: return "speaker.wave.3.fill"
    }
}
