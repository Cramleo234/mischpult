import MischpultCore
import SwiftUI

/// Das Fenster unter dem Menüleisten-Symbol.
struct MixerView: View {
    @EnvironmentObject private var store: MixerStore
    @AppStorage(GlassSettings.key) private var glassIntensity = GlassSettings.defaultIntensity
    @State private var showSettings = false
    /// Zuletzt gemessene Höhe der Regler-Ansicht; die Einstellungen bekommen genau
    /// diese Höhe, damit sich das Fenster beim Umschalten nicht verändert.
    @State private var mainHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Header(showSettings: $showSettings)
            GlassGroup(spacing: 12) {
                // Immer nur eine Ansicht zeigen: Glasflächen ignorieren Deckkraft-
                // Änderungen, übereinandergelegte Ebenen wären beide sichtbar.
                // Die Einstellungen übernehmen die Höhe der Regler-Ansicht (bei Bedarf
                // scrollbar), damit das Menüleisten-Fenster nicht verrutscht.
                if showSettings {
                    ScrollView {
                        SettingsTile(intensity: $glassIntensity)
                    }
                    .scrollIndicators(.automatic)
                    .frame(height: mainHeight > 0 ? mainHeight : nil)
                } else {
                    VStack(spacing: 10) {
                        if store.permission == .denied { PermissionBanner() }
                        DeviceTile()
                        AppsTile()
                    }
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { mainHeight = proxy.size.height }
                                .onChange(of: proxy.size.height) { _, height in mainHeight = height }
                        }
                    }
                }
            }
            Text("Unveränderte Apps laufen direkt zum Gerät.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(14)
        .frame(width: 360)
        .environment(\.glassIntensity, glassIntensity)
        .onAppear { store.setVisible(true) }
        .onDisappear {
            store.setVisible(false)
            showSettings = false
        }
    }
}

// MARK: Kopfzeile

private struct Header: View {
    @EnvironmentObject private var store: MixerStore
    @Binding var showSettings: Bool

    private var subtitle: String {
        let playing = store.apps.filter(\.isPlaying).count
        switch playing {
        case 0: return L("Keine App spielt Ton")
        case 1: return L("1 App spielt Ton")
        default: return String(format: L("%d Apps spielen Ton"), playing)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.vertical.3")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .glassCircle(tint: .accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Mischpult")
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: showSettings ? "xmark" : "gearshape.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassCircle(interactive: true)
            .help(showSettings ? L("Einstellungen schließen") : L("Einstellungen"))
            .accessibilityLabel(showSettings ? Text("Einstellungen schließen") : Text("Einstellungen"))
        }
        .padding(.horizontal, 2)
    }
}

// MARK: Hinweis zur Erlaubnis

private struct PermissionBanner: View {
    @EnvironmentObject private var store: MixerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Zugriff auf Systemaudio fehlt", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
            Text("Mischpult braucht die Erlaubnis „Nur Systemaudio aufnehmen“, um die Lautstärke einzelner Apps zu regeln.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Systemeinstellungen öffnen") { store.openPermissionSettings() }
                .controlSize(.small)
                .glassButtonStyle()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassTile(tint: .orange.opacity(0.25))
    }
}

// MARK: Geräte

private struct DeviceTile: View {
    @EnvironmentObject private var store: MixerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DevicePicker(title: "Ausgabe", device: store.defaultOutput, devices: store.outputs,
                         fallbackSymbol: "speaker.slash", select: store.selectOutput)
            HStack(spacing: 8) {
                Button { store.toggleMasterMute() } label: {
                    Image(systemName: speakerSymbol(store.masterMuted ? 0 : store.masterVolume))
                        .frame(width: 22)
                }
                .buttonStyle(.borderless)
                .help(store.masterMuted ? L("Ton einschalten") : L("Stummschalten"))
                Slider(value: Binding(get: { store.masterVolume },
                                      set: { store.setMasterVolume($0) }), in: 0...1)
                    .controlSize(.small)
                    .disabled(!store.masterHasVolume)
                    .accessibilityLabel(Text("Gesamtlautstärke"))
                Text(store.masterHasVolume ? percent(store.masterVolume) : "–")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }

            Divider().opacity(0.5)

            DevicePicker(title: "Eingabe", device: store.defaultInput, devices: store.inputs,
                         fallbackSymbol: "mic.slash", select: store.selectInput)
            if store.inputHasVolume {
                HStack(spacing: 8) {
                    Image(systemName: "mic")
                        .frame(width: 22)
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(get: { store.inputVolume },
                                          set: { store.setInputVolume($0) }), in: 0...1)
                        .controlSize(.small)
                        .accessibilityLabel(Text("Mikrofonpegel"))
                    Text(percent(store.inputVolume))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .glassTile()
    }
}

private struct DevicePicker: View {
    let title: LocalizedStringKey
    let device: AudioDevice?
    let devices: [AudioDevice]
    let fallbackSymbol: String
    let select: (AudioDevice) -> Void

    var body: some View {
        Menu {
            ForEach(devices) { candidate in
                Button {
                    select(candidate)
                } label: {
                    if candidate.id == device?.id {
                        Label(candidate.name, systemImage: "checkmark")
                    } else {
                        Label(candidate.name, systemImage: candidate.symbolName)
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: device?.symbolName ?? fallbackSymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .glassCircle(tint: .accentColor)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(device?.name ?? L("Kein Gerät"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
    }
}

// MARK: Apps

private struct AppsTile: View {
    @EnvironmentObject private var store: MixerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Apps")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            if store.apps.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "speaker.zzz.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .symbolEffect(.pulse, options: .repeating)
                    Text("Gerade spielt keine App Ton ab.")
                        .font(.callout.weight(.medium))
                    Text("Sobald eine App Ton ausgibt, erscheint sie hier.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .padding(.bottom, 4)
            } else {
                // Das Menüleisten-Fenster misst seine Größe beim Öffnen. Eine Scroll-Ansicht
                // ohne feste Höhe kann dabei auf null schrumpfen (leeres/abgeschnittenes
                // Fenster). Darum: wenige Apps ohne Scrollen, viele mit fester Höhe.
                if store.apps.count <= Self.maxRowsWithoutScrolling {
                    rows
                } else {
                    ScrollView { rows }
                        .scrollIndicators(.automatic)
                        .frame(height: 430)
                }
            }
        }
        .glassTile()
    }

    static let maxRowsWithoutScrolling = 6

    private var rows: some View {
        VStack(spacing: 2) {
            ForEach(store.apps) { app in
                AppRow(app: app)
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }
}

private struct AppRow: View {
    @EnvironmentObject private var store: MixerStore
    let app: AppEntry
    @State private var hovering = false

    private var expanded: Bool { store.expandedApp == app.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button { store.toggleMute(app.id) } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Image(nsImage: app.icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 32, height: 32)
                            .saturation(app.settings.muted ? 0 : 1)
                            .opacity(app.settings.muted ? 0.45 : 1)
                        if app.settings.muted {
                            Image(systemName: "speaker.slash.circle.fill")
                                .font(.system(size: 14))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .red)
                                .offset(x: 4, y: 4)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(app.settings.muted ? L("Ton einschalten") : L("Stummschalten"))
                .accessibilityLabel(app.settings.muted
                                    ? Text("\(app.name): Ton einschalten") : Text("\(app.name): Stummschalten"))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Text(app.name)
                            .font(.system(size: 12.5, weight: .medium))
                            .lineLimit(1)
                        badges
                        Spacer(minLength: 4)
                        Text(app.settings.muted ? L("Stumm") : percent(app.settings.volume))
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(app.settings.volume > 1.005 && !app.settings.muted
                                             ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    }
                    VolumeSlider(value: Binding(get: { app.settings.volume },
                                                set: { store.setVolume(app.id, $0) }),
                                 level: app.level, muted: app.settings.muted)
                        .accessibilityLabel(Text("Lautstärke \(app.name)"))
                }

                Button {
                    // Ohne Animation: eine animierte Höhenänderung lässt das
                    // Menüleisten-Fenster verrutschen.
                    store.expandedApp = expanded ? nil : app.id
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassCircle(interactive: true)
                .help(L("Ausgabe und Equalizer"))
                .accessibilityLabel(Text("Ausgabe und Equalizer"))
            }
            if let error = app.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.leading, 42)
            }
            if expanded {
                AppDetails(app: app)
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(expanded ? 0.07 : (hovering ? 0.045 : 0)))
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: app.settings.muted)
    }

    @ViewBuilder private var badges: some View {
        if let uid = app.settings.outputUID, let device = store.outputs.first(where: { $0.uid == uid }) {
            Image(systemName: device.symbolName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .help(device.name)
        }
        if !app.settings.eq.isFlat {
            Image(systemName: "slider.horizontal.3")
                .font(.caption2)
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
        VStack(spacing: 3) {
            Slider(value: Binding(get: { Double(value) }, set: { newValue in
                // Bei 100 % leicht einrasten, damit man den Normalwert sicher trifft.
                value = abs(newValue - 1) < 0.04 ? 1 : Float(newValue)
            }), in: 0...Double(AppSettings.volumeRange.upperBound))
            .controlSize(.small)
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
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("Ausgabe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)
                Menu {
                    Button {
                        store.setOutput(app.id, nil)
                    } label: {
                        if app.settings.outputUID == nil {
                            Label("Systemausgabe", systemImage: "checkmark")
                        } else {
                            Text("Systemausgabe")
                        }
                    }
                    Divider()
                    ForEach(store.outputs) { device in
                        Button {
                            store.setOutput(app.id, device.uid)
                        } label: {
                            if app.settings.outputUID == device.uid {
                                Label(device.name, systemImage: "checkmark")
                            } else {
                                Label(device.name, systemImage: device.symbolName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(outputName).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                    .font(.caption.weight(.medium))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
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
                Button("Zurücksetzen") {
                    withAnimation(.smooth) { store.reset(app.id) }
                }
                .controlSize(.small)
                .glassButtonStyle()
                .disabled(!app.settings.needsTap)
            }
        }
        .padding(.leading, 42)
        .padding(.trailing, 4)
    }

    private var outputName: String {
        guard let uid = app.settings.outputUID else { return L("Systemausgabe") }
        return store.outputs.first { $0.uid == uid }?.name ?? L("Gerät nicht verbunden")
    }
}

private struct EQRow: View {
    let title: LocalizedStringKey
    let value: Float
    let onChange: (Float) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Slider(value: Binding(get: { Double(value) }, set: { newValue in
                onChange(abs(newValue) < 0.6 ? 0 : Float(newValue.rounded()))
            }), in: Double(EQSettings.range.lowerBound)...Double(EQSettings.range.upperBound))
            .controlSize(.mini)
            .accessibilityLabel(Text(title))
            Text(String(format: "%+.0f dB", value))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

// MARK: Einstellungen

private struct SettingsTile: View {
    @EnvironmentObject private var store: MixerStore
    @Binding var intensity: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Einstellungen")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Toggle("Alle Apps anzeigen", isOn: $store.showAllApps)
            Toggle("Beim Anmelden starten", isOn: Binding(get: { store.launchAtLogin },
                                                          set: { store.setLaunchAtLogin($0) }))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Glas-Intensität")
                    Spacer()
                    Text(Double(intensity).formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $intensity, in: 0...1)
                    .controlSize(.small)
                    .accessibilityLabel(Text("Glas-Intensität"))
                Text("Weniger Intensität macht die Flächen ruhiger und deckender.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Divider().opacity(0.5)

            VStack(spacing: 2) {
                SettingsLink(title: "Ton-Einstellungen öffnen …", symbol: "speaker.wave.2") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                }
                SettingsLink(title: "Erlaubnis Systemaudio …", symbol: "lock.shield") {
                    store.openPermissionSettings()
                }
                SettingsLink(title: "Versionsverlauf …", symbol: "clock.arrow.circlepath") {
                    ChangelogWindow.show()
                }
            }

            HStack {
                Text(aboutText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Beenden") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
                    .controlSize(.small)
                    .glassButtonStyle()
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.system(size: 12.5))
        .padding(12)
        .glassTile()
    }

    private var aboutText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        return String(format: L("Mischpult %@ – ein Hobbyprojekt"), version)
    }
}

private struct SettingsLink: View {
    let title: LocalizedStringKey
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.07 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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
