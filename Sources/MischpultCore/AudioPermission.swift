import Foundation

/// Erlaubnis „Nur Systemaudio aufnehmen“, ohne die Process-Taps stumm bleiben.
///
/// Apple bietet dafür keine öffentliche Abfrage; wie bei vielen Audio-Werkzeugen
/// wird das TCC-Framework dynamisch geladen. Fehlt es, gilt der Status als „nicht abfragbar“.
public enum AudioPermission {
    /// `notDetermined`: noch nie gefragt. `unavailable`: Abfrage nicht möglich
    /// (dann einfach versuchen – macOS fragt beim ersten Tap selbst).
    public enum Status: Sendable { case granted, denied, notDetermined, unavailable }

    private static let service = "kTCCServiceAudioCapture" as CFString
    private static let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int

    public static var status: Status {
        guard let handle, let symbol = dlsym(handle, "TCCAccessPreflight") else { return .unavailable }
        switch unsafeBitCast(symbol, to: Preflight.self)(service, nil) {
        case 0: return .granted
        case 1: return .denied
        default: return .notDetermined
        }
    }

    /// „Bildschirm- & Systemaudioaufnahme“ – dort steht auch „Nur Systemaudio“.
    public static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
}

/// Gespeicherte Regler einer App.
public struct AppSettings: Codable, Equatable, Sendable {
    public var volume: Float = 1
    public var muted = false
    /// UID des Ausgabegeräts; nil = folgt der Systemausgabe.
    public var outputUID: String?
    public var eq = EQSettings.flat

    public init() {}

    public static let volumeRange: ClosedRange<Float> = 0...2
    public var effectiveGain: Float { muted ? 0 : volume }
    /// Unveränderte Apps laufen ohne Tap direkt zum Gerät.
    public var needsTap: Bool { muted || abs(volume - 1) > 0.005 || outputUID != nil || !eq.isFlat }
}
