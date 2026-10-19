import AppKit
import MischpultCore
@preconcurrency import UserNotifications

/// macOS-Mitteilung, wenn Bluetooth-Kopfhörer in den Telefon-Modus wechseln –
/// mit dem Knopf „Telefon-Modus beenden“.
@MainActor
final class CallModeNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = CallModeNotifier()
    nonisolated private static let categoryID = "callMode"
    nonisolated private static let fixActionID = "fixCallMode"
    nonisolated private static let requestID = "callMode"

    private weak var store: MixerStore?
    /// Ohne App-Bundle (Testbuild) gibt es keine Mitteilungszentrale.
    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    func setUp(store: MixerStore) {
        self.store = store
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let fix = UNNotificationAction(identifier: Self.fixActionID, title: L("Telefon-Modus beenden"))
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.categoryID, actions: [fix],
                                                                 intentIdentifiers: [])])
    }

    func notify(_ status: CallModeStatus) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = String(format: L("%@ im Telefon-Modus"), status.deviceName)
        content.body = CallModeText.explanation(status)
        if status.defaultInputIsBluetooth { content.categoryIdentifier = Self.categoryID }
        let request = UNNotificationRequest(identifier: Self.requestID, content: content, trigger: nil)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            UNUserNotificationCenter.current().add(request)
        }
    }

    func clear() {
        guard available else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.requestID])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let fix = response.actionIdentifier == Self.fixActionID
        DispatchQueue.main.async {
            MainActor.assumeIsolated { if fix { self.store?.fixCallMode() } }
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}

/// Erklärtexte zum Telefon-Modus (Mitteilung und Hinweis im Fenster).
enum CallModeText {
    static func explanation(_ status: CallModeStatus) -> String {
        let apps = ListFormatter.localizedString(byJoining: status.appNames)
        if status.defaultInputIsBluetooth {
            return String(format: L("%@ benutzt das Kopfhörer-Mikrofon, dadurch klingt der Ton schlechter. Mischpult kann auf das eingebaute Mikrofon umschalten."), apps)
        }
        return String(format: L("%@ hat das Kopfhörer-Mikrofon fest gewählt, dadurch klingt der Ton schlechter. Stelle dort das Mikrofon auf „Standard“ oder das eingebaute Mikrofon."), apps)
    }
}
