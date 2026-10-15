import MischpultCore
import SwiftUI

/// Das Fenster unter dem Menüleisten-Symbol.
struct MixerView: View {
    @EnvironmentObject private var store: MixerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if store.permission == .denied { PermissionBanner() }
            DeviceSection()
            AppsSection()
            footer
        }
        .padding(14)
        .frame(width: 380)
        .onAppear { store.setVisible(true) }
        .onDisappear { store.setVisible(false) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "slider.vertical.3")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Mischpult")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            OptionsMenu()
        }
    }

    private var footer: some View {
        HStack {
            Text("Unveränderte Apps laufen direkt zum Gerät.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: Hinweis zur Erlaubnis

private struct PermissionBanner: View {
    @EnvironmentObject private var store: MixerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Zugriff auf Systemaudio fehlt", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
            Text("Mischpult braucht die Erlaubnis „Nur Systemaudio aufnehmen“, um die Lautstärke einzelner Apps zu regeln.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Erlauben …") { store.requestPermission() }
                Button("Systemeinstellungen öffnen") { store.openPermissionSettings() }
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: Geräte

private struct DeviceSection: View {
    @EnvironmentObject private var store: MixerStore

    var body: some View {
        Card {
            VStack(spacing: 10) {
                deviceRow(title: "Ausgabe", device: store.defaultOutput, devices: store.outputs,
                          select: store.selectOutput)
                HStack(spacing: 8) {
                    Button { store.toggleMasterMute() } label: {
                        Image(systemName: speakerSymbol(store.masterMuted ? 0 : store.masterVolume))
                            .frame(width: 22)
                    }
                    .buttonStyle(.borderless)
                    .help(store.masterMuted ? L("Ton einschalten") : L("Stummschalten"))
                    Slider(value: Binding(get: { store.masterVolume },
                                          set: { store.setMasterVolume($0) }), in: 0...1)
                        .disabled(!store.masterHasVolume)
                    Text(store.masterHasVolume ? percent(store.masterVolume) : "–")
                        .monospacedDigit()
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                Divider()
                deviceRow(title: "Eingabe", device: store.defaultInput, devices: store.inputs,
                          select: store.selectInput)
                if store.inputHasVolume {
                    HStack(spacing: 8) {
                        Image(systemName: "mic").frame(width: 22).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { store.inputVolume },
                                              set: { store.setInputVolume($0) }), in: 0...1)
                        Text(percent(store.inputVolume))
                            .monospacedDigit()
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func deviceRow(title: LocalizedStringKey, device: AudioDevice?, devices: [AudioDevice],
                           select: @escaping (AudioDevice) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Menu {
                ForEach(devices) { candidate in
                    Button {
                        select(candidate)
                    } label: {
                        if candidate.id == device?.id {
                            Label(candidate.name, systemImage: "checkmark")
                        } else {
                            Text(candidate.name)
                        }
                    }
                }
            } label: {
                Label(device?.name ?? L("Kein Gerät"), systemImage: device?.symbolName ?? "speaker.slash")
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: Apps

private struct AppsSection: View {
    @EnvironmentObject private var store: MixerStore

    var body: some View {
        Card(padding: 0) {
            if store.apps.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "speaker.zzz")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Gerade spielt keine App Ton ab.")
                        .font(.callout)
                    Text("Sobald eine App Ton ausgibt, erscheint sie hier.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(store.apps.enumerated()), id: \.element.id) { index, app in
                            if index > 0 { Divider().padding(.leading, 50) }
                            AppRow(app: app)
                        }
                    }
                }
                .frame(maxHeight: 420)
                .fixedSize(horizontal: false, vertical: store.apps.count <= 5)
            }
        }
    }
}

private struct AppRow: View {
    @EnvironmentObject private var store: MixerStore
    let app: AppEntry

    private var expanded: Bool { store.expandedApp == app.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button { store.toggleMute(app.id) } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Image(nsImage: app.icon)
                            .resizable()
                            .frame(width: 30, height: 30)
                            .opacity(app.settings.muted ? 0.4 : 1)
                        if app.settings.muted {
                            Image(systemName: "speaker.slash.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.white, .red)
                                .offset(x: 3, y: 3)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(app.settings.muted ? L("Ton einschalten") : L("Stummschalten"))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(app.name)
                            .font(.system(size: 12.5, weight: .medium))
                            .lineLimit(1)
                        if app.settings.outputUID != nil, let device = store.outputs.first(where: {
                            $0.uid == app.settings.outputUID
                        }) {
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
                        Spacer(minLength: 4)
                        Text(app.settings.muted ? L("Stumm") : percent(app.settings.volume))
                            .monospacedDigit()
                            .font(.caption)
                            .foregroundStyle(app.settings.volume > 1 && !app.settings.muted ? .orange : .secondary)
                    }
                    VolumeSlider(value: Binding(get: { app.settings.volume },
                                                set: { store.setVolume(app.id, $0) }),
                                 level: app.level, muted: app.settings.muted)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        store.expandedApp = expanded ? nil : app.id
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(L("Ausgabe und Equalizer"))
            }
            if let error = app.error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.leading, 40)
            }
            if expanded {
                AppDetails(app: app)
                    .padding(.leading, 40)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }
}

/// Lautstärkeregler 0–200 % mit Pegelanzeige und Markierung bei 100 %.
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
            .opacity(muted ? 0.5 : 1)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(LinearGradient(colors: [.green, .yellow, .orange],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * CGFloat(min(level, 1)))
                        .mask(alignment: .leading) { Capsule() }
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 2)
            .opacity(level > 0 ? 1 : 0.4)
        }
    }
}

private struct AppDetails: View {
    @EnvironmentObject private var store: MixerStore
    let app: AppEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Ausgabe")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
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
                                Text(device.name)
                            }
                        }
                    }
                } label: {
                    Text(outputName)
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
            }
            EQSlider(title: "Bässe", value: app.settings.eq.bass) { value in
                var eq = app.settings.eq; eq.bass = value; store.setEQ(app.id, eq)
            }
            EQSlider(title: "Mitten", value: app.settings.eq.mid) { value in
                var eq = app.settings.eq; eq.mid = value; store.setEQ(app.id, eq)
            }
            EQSlider(title: "Höhen", value: app.settings.eq.treble) { value in
                var eq = app.settings.eq; eq.treble = value; store.setEQ(app.id, eq)
            }
            HStack {
                Spacer()
                Button("Zurücksetzen") { store.reset(app.id) }
                    .controlSize(.small)
                    .disabled(!app.settings.needsTap)
            }
        }
    }

    private var outputName: String {
        guard let uid = app.settings.outputUID else { return L("Systemausgabe") }
        return store.outputs.first { $0.uid == uid }?.name ?? L("Gerät nicht verbunden")
    }
}

private struct EQSlider: View {
    let title: LocalizedStringKey
    let value: Float
    let onChange: (Float) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Slider(value: Binding(get: { Double(value) }, set: { newValue in
                onChange(abs(newValue) < 0.6 ? 0 : Float(newValue.rounded()))
            }), in: Double(EQSettings.range.lowerBound)...Double(EQSettings.range.upperBound))
            .controlSize(.mini)
            Text(String(format: "%+.0f dB", value))
                .monospacedDigit()
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
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
            Divider()
            Text(aboutText)
            Button("Mischpult beenden") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var aboutText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        return String(format: L("Mischpult %@ – privat"), version)
    }
}

// MARK: Bausteine

private struct Card<Content: View>: View {
    var padding: CGFloat = 10
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.quaternary))
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
