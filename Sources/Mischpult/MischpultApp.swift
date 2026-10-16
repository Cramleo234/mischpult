import AppKit
import SwiftUI

@main
struct MischpultApp: App {
    @StateObject private var store = MixerStore()

    init() {
        if let folder = ProcessInfo.processInfo.environment["MISCHPULT_UIAUDIT"] {
            // Prüfmodus der Oberfläche: läuft ohne Menüleisten-Symbol und beendet sich selbst.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    NSApp.setActivationPolicy(.prohibited)
                    UIAudit.run(into: URL(fileURLWithPath: folder))
                    exit(0)
                }
            }
        }
        if ProcessInfo.processInfo.environment["MISCHPULT_SELFTEST"] == "1" {
            print(MixerStore.selfTestReport())
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MixerView()
                .environmentObject(store)
        } label: {
            Image(systemName: "slider.vertical.3")
                .accessibilityLabel("Mischpult")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Lokalisiert Strings, die nicht als SwiftUI-Literal vorliegen.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Lautstärke als Prozent-Text („85 %“).
func percent(_ value: Float) -> String {
    Double(value).formatted(.percent.precision(.fractionLength(0)))
}
