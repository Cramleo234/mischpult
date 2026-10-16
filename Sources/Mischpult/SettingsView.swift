import AppKit
import SwiftUI

/// Normale Fenster neben dem Menüleisten-Fenster (Einstellungen, Versionsverlauf).
///
/// Das Menüleisten-Fenster selbst ändert nie seinen Inhalt: Jede Größenänderung
/// dort lässt es verrutschen. Deshalb öffnen sich Einstellungen in einem eigenen Fenster.
@MainActor
enum AuxWindow {
    private static var windows: [String: NSWindow] = [:]

    static func show<Content: View>(id: String, title: String, transparentTitlebar: Bool = false,
                                    content: () -> Content) {
        let window = windows[id] ?? {
            let created = NSWindow(contentViewController: NSHostingController(rootView: content()))
            created.title = title
            created.styleMask = [.titled, .closable, .fullSizeContentView]
            if transparentTitlebar {
                created.titlebarAppearsTransparent = true
                created.titleVisibility = .hidden
                created.isMovableByWindowBackground = true
            }
            created.isReleasedWhenClosed = false
            created.center()
            windows[id] = created
            return created
        }()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

enum SettingsWindow {
    @MainActor
    static func show(store: MixerStore) {
        AuxWindow.show(id: "settings", title: L("Mischpult – Einstellungen")) {
            SettingsView().environmentObject(store)
        }
    }
}

/// Einstellungen im üblichen macOS-Stil (gruppiertes Formular).
struct SettingsView: View {
    @EnvironmentObject private var store: MixerStore
    @AppStorage(GlassSettings.key) private var intensity = GlassSettings.defaultIntensity

    var body: some View {
        Form {
            Section("Allgemein") {
                Toggle("Alle Apps anzeigen", isOn: $store.showAllApps)
                Toggle("Beim Anmelden starten", isOn: Binding(get: { store.launchAtLogin },
                                                              set: { store.setLaunchAtLogin($0) }))
                if store.launchAtLoginNeedsApproval {
                    Text("macOS möchte das noch bestätigt haben: Systemeinstellungen → Allgemein → Anmeldeobjekte.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Glas-Intensität") {
                    HStack {
                        Slider(value: $intensity, in: 0...1)
                            .frame(width: 180)
                            .accessibilityLabel(Text("Glas-Intensität"))
                        Text(intensity.formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            } header: {
                Text("Darstellung")
            } footer: {
                Text("Weniger Intensität macht die Flächen ruhiger und deckender.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("System") {
                Button("Ton-Einstellungen öffnen …") { store.openSoundSettings() }
                Button("Erlaubnis Systemaudio …") { store.openPermissionSettings() }
            }

            Section {
                LabeledContent("Version", value: version)
                Button("Versionsverlauf …") { ChangelogWindow.show() }
                Button("Mischpult beenden") { NSApp.terminate(nil) }
            } footer: {
                Text("Mischpult – ein Hobbyprojekt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .buttonStyle(.link)
        // Feste Größe: ein Formular berechnet seine Höhe sonst selbst und kann
        // dabei – wie früher die App-Liste – auf null schrumpfen.
        .frame(width: 440, height: 500)
        .onAppear { store.refreshLaunchAtLogin() }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }
}
