import Foundation

/// Lautstärke der Hinweis- und Mitteilungstöne („Hinweis-Lautstärke“ in den
/// Ton-Einstellungen von macOS), unabhängig von der Gesamtlautstärke.
///
/// macOS bietet dafür den offiziellen AppleScript-Befehl `volume settings`. Er läuft
/// bewusst in einem eigenen `osascript`-Prozess im Hintergrund: `NSAppleScript` im
/// eigenen Prozess lässt die Ereignisschleife weiterlaufen und kann so mitten in
/// einem SwiftUI-Update andere Arbeit ausführen – das bringt SwiftUI zum Absturz.
public enum AlertVolume {
    private static let queue = DispatchQueue(label: "local.private.mischpult.alertvolume")
    private static let lock = NSLock()
    private static var pendingValue: Int?
    private static var writerRunning = false

    /// Liest den Wert im Hintergrund; Ergebnis (0 … 1 oder nil) auf dem Haupt-Thread.
    public static func get(_ completion: @escaping @Sendable (Float?) -> Void) {
        queue.async {
            let value = readNow()
            DispatchQueue.main.async { completion(value) }
        }
    }

    /// Blockierend lesen – nur für den Selbsttest ohne Oberfläche.
    public static func readNow() -> Float? {
        guard let output = osascript("alert volume of (get volume settings)"),
              let number = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return fraction(fromScript: number)
    }

    /// Setzt den Wert im Hintergrund. Beim Ziehen am Regler werden Zwischenwerte
    /// zusammengefasst: Es läuft immer höchstens ein Prozess, danach der neueste Wert.
    public static func set(_ value: Float) {
        lock.lock()
        pendingValue = scriptValue(value)
        let startWriter = !writerRunning
        writerRunning = true
        lock.unlock()
        guard startWriter else { return }
        queue.async {
            while true {
                lock.lock()
                guard let next = pendingValue else {
                    writerRunning = false
                    lock.unlock()
                    return
                }
                pendingValue = nil
                lock.unlock()
                _ = osascript("set volume alert volume \(next)")
            }
        }
    }

    /// AppleScript erwartet ganze Prozent 0 … 100.
    public static func scriptValue(_ value: Float) -> Int {
        Int((min(max(value, 0), 1) * 100).rounded())
    }

    public static func fraction(fromScript value: Int) -> Float {
        Float(min(max(value, 0), 100)) / 100
    }

    private static func osascript(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
