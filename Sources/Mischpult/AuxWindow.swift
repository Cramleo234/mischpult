import AppKit
import SwiftUI

/// Normales Fenster neben dem Menüleisten-Fenster (z. B. Versionsverlauf).
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
