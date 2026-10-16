import AppKit
import SwiftUI

/// Meldet zuverlässig, ob das Fenster, in dem die Ansicht steckt, gerade sichtbar ist.
///
/// `onAppear`/`onDisappear` reichen beim Menüleisten-Fenster nicht: Es wird beim
/// Schließen nur ausgeblendet, `onDisappear` kommt dann nicht zuverlässig. Hier wird
/// stattdessen der Sichtbarkeitszustand des Fensters selbst beobachtet.
struct WindowVisibilityObserver: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onChange = onChange
    }

    final class ObserverView: NSView {
        var onChange: ((Bool) -> Void)?
        private var tokens: [NSObjectProtocol] = []
        private var lastReported: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens = []
            guard let window else {
                report(false)
                return
            }
            let names: [Notification.Name] = [NSWindow.didChangeOcclusionStateNotification,
                                              NSWindow.didBecomeKeyNotification,
                                              NSWindow.didResignKeyNotification,
                                              NSWindow.willCloseNotification]
            for name in names {
                tokens.append(NotificationCenter.default.addObserver(forName: name, object: window,
                                                                      queue: .main) { [weak self] note in
                    guard let self, let window = self.window else { return }
                    let closing = note.name == NSWindow.willCloseNotification
                    self.report(!closing && window.isVisible && window.occlusionState.contains(.visible))
                })
            }
            report(window.isVisible && window.occlusionState.contains(.visible))
        }

        private func report(_ visible: Bool) {
            guard visible != lastReported else { return }
            lastReported = visible
            onChange?(visible)
        }

        deinit {
            tokens.forEach(NotificationCenter.default.removeObserver)
        }
    }
}
