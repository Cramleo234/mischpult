import MischpultCore
import SwiftUI

/// Das Fenster unter dem Menüleisten-Symbol.
struct MixerView: View {
    @EnvironmentObject private var store: MixerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Header()
            GlassGroup(spacing: 12) {
                VStack(spacing: 10) {
                    if store.permission == .denied { PermissionBanner() }
                    DeviceTile()
                    AppsTile()
                }
            }
            Text("Unveränderte Apps laufen direkt zum Gerät.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(14)
        .frame(width: 360)
        .onAppear { store.setVisible(true) }
        .onDisappear { store.setVisible(false) }
    }
}

// MARK: Kopfzeile

private struct Header: View {
    @EnvironmentObject private var store: MixerStore

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
            OptionsMenu()
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
            PillSlider(value: Binding(get: { Double(store.masterMuted ? 0 : store.masterVolume) },
                                      set: { store.setMasterVolume(Float($0)) }),
                       symbol: speakerSymbol(store.masterMuted ? 0 : store.masterVolume),
                       dimmed: !store.masterHasVolume,
                       accessibilityLabel: Text("Gesamtlautstärke"),
                       accessibilityValue: percent(store.masterVolume),
                       onSymbolTap: { store.toggleMasterMute() })
                .disabled(!store.masterHasVolume)
                .help(store.masterMuted ? L("Ton einschalten") : L("Stummschalten"))

            Divider().opacity(0.5)

            DevicePicker(title: "Eingabe", device: store.defaultInput, devices: store.inputs,
                         fallbackSymbol: "mic.slash", select: store.selectInput)
            if store.inputHasVolume {
                PillSlider(value: Binding(get: { Double(store.inputVolume) },
                                          set: { store.setInputVolume(Float($0)) }),
                           symbol: "mic.fill", height: 22,
                           accessibilityLabel: Text("Mikrofonpegel"),
                           accessibilityValue: percent(store.inputVolume))
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
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.apps) { app in
                            AppRow(app: app)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 400)
                .fixedSize(horizontal: false, vertical: store.apps.count <= 5)
            }
        }
        .glassTile()
        .animation(.smooth(duration: 0.25), value: store.apps.map(\.id))
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
                    PillSlider(value: Binding(get: { Double(app.settings.volume) },
                                              set: { store.setVolume(app.id, Float($0)) }),
                               range: 0...Double(AppSettings.volumeRange.upperBound),
                               mark: 1, height: 20, dimmed: app.settings.muted,
                               accessibilityLabel: Text("Lautstärke \(app.name)"),
                               accessibilityValue: percent(app.settings.volume))
                    LevelBar(level: app.level)
                }

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        store.expandedApp = expanded ? nil : app.id
                    }
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
                    .transition(.opacity.combined(with: .move(edge: .top)))
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
            PillSlider(value: Binding(get: { Double(value) },
                                      set: { onChange(Float($0.rounded())) }),
                       range: Double(EQSettings.range.lowerBound)...Double(EQSettings.range.upperBound),
                       origin: 0, height: 14,
                       accessibilityLabel: Text(title),
                       accessibilityValue: String(format: "%+.0f dB", value),
                       step: 1)
            Text(String(format: "%+.0f dB", value))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

// MARK: Optionen

private struct OptionsMenu: View {
    @EnvironmentObject private var store: MixerStore

    var body: some View {
        Menu {
            Toggle("Alle Apps anzeigen", isOn: $store.showAllApps)
            Toggle("Beim Anmelden starten", isOn: Binding(get: { store.launchAtLogin },
                                                          set: { store.setLaunchAtLogin($0) }))
            Divider()
            Button("Ton-Einstellungen öffnen …") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
            }
            Button("Erlaubnis Systemaudio …") { store.openPermissionSettings() }
            Button("Versionsverlauf …") { ChangelogWindow.show() }
            Divider()
            Text(aboutText)
            Button("Mischpult beenden") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .glassCircle(interactive: true)
        .accessibilityLabel(Text("Optionen"))
    }

    private var aboutText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        return String(format: L("Mischpult %@ – ein Hobbyprojekt"), version)
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
