import CoreAudio

/// Telefon-Modus von Bluetooth-Kopfhörern: Sobald eine App ihr Mikrofon benutzt,
/// schaltet Bluetooth auf einen Sprech-Modus mit deutlich schlechterem Klang.
public struct CallModeStatus: Equatable, Sendable {
    /// Name der Kopfhörer.
    public let deviceName: String
    /// Apps, die gerade über das Kopfhörer-Mikrofon aufnehmen.
    public let appNames: [String]
    /// Ist das Kopfhörer-Mikrofon der Standard-Eingang von macOS? Dann hilft es,
    /// den Standard-Eingang umzustellen. Sonst hat die App das Mikrofon fest gewählt.
    public let defaultInputIsBluetooth: Bool

    public init(deviceName: String, appNames: [String], defaultInputIsBluetooth: Bool) {
        self.deviceName = deviceName
        self.appNames = appNames
        self.defaultInputIsBluetooth = defaultInputIsBluetooth
    }
}

public enum BluetoothCallMode {
    /// Erkennt den Telefon-Modus aus den Audio-Prozessen und Geräten.
    public static func detect(groups: [AudioAppGroup], devices: [AudioDevice],
                              defaultInputID: AudioObjectID) -> CallModeStatus? {
        let bluetoothInputs = devices.filter { $0.isBluetooth && $0.hasInput }
        let bluetoothIDs = Set(bluetoothInputs.map(\.id))
        guard !bluetoothIDs.isEmpty else { return nil }
        var names: [String] = []
        var usedDevice: AudioDevice?
        for group in groups {
            for process in group.processes where process.isRunningInput {
                if let match = process.inputDeviceIDs.first(where: bluetoothIDs.contains) {
                    if !names.contains(group.name) { names.append(group.name) }
                    usedDevice = usedDevice ?? bluetoothInputs.first { $0.id == match }
                }
            }
        }
        guard let usedDevice else { return nil }
        return CallModeStatus(deviceName: usedDevice.name, appNames: names.sorted(),
                              defaultInputIsBluetooth: bluetoothIDs.contains(defaultInputID))
    }
}
