import CoreAudio
import AudioToolbox
import Foundation

/// Ein Audiogerät (Lautsprecher, Kopfhörer, Mikrofon …).
public struct AudioDevice: Identifiable, Hashable, Sendable {
    public let id: AudioObjectID
    public let uid: String
    public let name: String
    public let hasOutput: Bool
    public let hasInput: Bool
    public let transportType: UInt32

    public init(id: AudioObjectID, uid: String, name: String, hasOutput: Bool, hasInput: Bool,
                transportType: UInt32) {
        self.id = id
        self.uid = uid
        self.name = name
        self.hasOutput = hasOutput
        self.hasInput = hasInput
        self.transportType = transportType
    }

    public var isBluetooth: Bool {
        transportType == kAudioDeviceTransportTypeBluetooth || transportType == kAudioDeviceTransportTypeBluetoothLE
    }

    /// SF-Symbol passend zur Geräteart.
    public var symbolName: String {
        let lower = name.lowercased()
        if lower.contains("airpods") { return "airpods" }
        switch transportType {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return lower.contains("headphone") || lower.contains("kopfhörer") ? "headphones" : "hifispeaker"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
        case kAudioDeviceTransportTypeUSB: return "cable.connector"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: return "waveform"
        default:
            if lower.contains("headphone") || lower.contains("kopfhörer") { return "headphones" }
            return hasInput && !hasOutput ? "mic" : "speaker.wave.2"
        }
    }
}

public enum AudioDevices {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    /// Alle Geräte ohne private (z. B. die eigenen Aggregate von Mischpult).
    public static func all() -> [AudioDevice] {
        let ids = (try? CAProperty.array(system, CAProperty.address(kAudioHardwarePropertyDevices),
                                         of: AudioObjectID.self, filler: 0)) ?? []
        return ids.compactMap(device(for:))
    }

    public static func outputs() -> [AudioDevice] { all().filter(\.hasOutput) }

    /// Ersatz-Eingang statt eines Bluetooth-Mikrofons: bevorzugt das eingebaute
    /// Mikrofon, sonst irgendein Eingang, der nicht über Bluetooth läuft.
    /// Benutzt eine App das Bluetooth-Mikrofon, schalten die Kopfhörer in den
    /// Telefon-Modus (schlechte Tonqualität) – das soll vermieden werden.
    public static func inputAvoidingBluetooth(_ inputs: [AudioDevice]) -> AudioDevice? {
        let candidates = inputs.filter { $0.hasInput && !$0.isBluetooth }
        return candidates.first { $0.transportType == kAudioDeviceTransportTypeBuiltIn } ?? candidates.first
    }
    public static func inputs() -> [AudioDevice] { all().filter(\.hasInput) }

    public static func device(for id: AudioObjectID) -> AudioDevice? {
        guard let uid = CAProperty.string(id, CAProperty.address(kAudioDevicePropertyDeviceUID)) else { return nil }
        // Eigene Aggregate (Taps) nie als Gerät anbieten.
        if uid.hasPrefix(AppTap.aggregateUIDPrefix) { return nil }
        let name = CAProperty.string(id, CAProperty.address(kAudioObjectPropertyName)) ?? uid
        let transport = (try? CAProperty.value(id, CAProperty.address(kAudioDevicePropertyTransportType),
                                               default: UInt32(0))) ?? 0
        return AudioDevice(id: id, uid: uid, name: name,
                           hasOutput: channelCount(id, scope: kAudioObjectPropertyScopeOutput) > 0,
                           hasInput: channelCount(id, scope: kAudioObjectPropertyScopeInput) > 0,
                           transportType: transport)
    }

    static func channelCount(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var address = CAProperty.address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    public static func defaultDevice(input: Bool = false) -> AudioObjectID {
        let selector = input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
        return (try? CAProperty.value(system, CAProperty.address(selector), default: AudioObjectID(0))) ?? 0
    }

    public static func setDefaultDevice(_ id: AudioObjectID, input: Bool = false) {
        let selector = input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
        try? CAProperty.set(system, CAProperty.address(selector), id)
        if !input {
            // Systemtöne folgen der Ausgabe, wie es auch die Systemeinstellungen tun.
            try? CAProperty.set(system, CAProperty.address(kAudioHardwarePropertyDefaultSystemOutputDevice), id)
        }
    }

    public static func deviceID(forUID uid: String) -> AudioObjectID? {
        all().first { $0.uid == uid }?.id
    }

    public static func uid(of id: AudioObjectID) -> String? {
        CAProperty.string(id, CAProperty.address(kAudioDevicePropertyDeviceUID))
    }

    public static func nominalSampleRate(_ id: AudioObjectID) -> Double {
        (try? CAProperty.value(id, CAProperty.address(kAudioDevicePropertyNominalSampleRate),
                               default: Float64(48_000))) ?? 48_000
    }

    // MARK: Lautstärke eines Geräts

    private static func volumeAddresses(_ id: AudioObjectID, scope: AudioObjectPropertyScope)
        -> [AudioObjectPropertyAddress] {
        let virtual = CAProperty.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: scope)
        if CAProperty.has(id, virtual) { return [virtual] }
        let main = CAProperty.address(kAudioDevicePropertyVolumeScalar, scope: scope)
        if CAProperty.has(id, main) { return [main] }
        // Manche Geräte haben nur Kanal-Regler (1 = links, 2 = rechts).
        return (1...2).map { CAProperty.address(kAudioDevicePropertyVolumeScalar, scope: scope, element: $0) }
            .filter { CAProperty.has(id, $0) }
    }

    /// Lautstärke 0…1 oder nil, wenn das Gerät keinen Regler hat (z. B. HDMI).
    public static func volume(_ id: AudioObjectID, input: Bool = false) -> Float? {
        let scope = input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        let values = volumeAddresses(id, scope: scope).compactMap {
            try? CAProperty.value(id, $0, default: Float32(0))
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Float(values.count)
    }

    public static func setVolume(_ id: AudioObjectID, _ value: Float, input: Bool = false) {
        let scope = input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        let clamped = Float32(min(max(value, 0), 1))
        for address in volumeAddresses(id, scope: scope) where CAProperty.isSettable(id, address) {
            try? CAProperty.set(id, address, clamped)
        }
    }

    public static func isMuted(_ id: AudioObjectID, input: Bool = false) -> Bool {
        let scope = input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        let address = CAProperty.address(kAudioDevicePropertyMute, scope: scope)
        guard CAProperty.has(id, address) else { return false }
        return ((try? CAProperty.value(id, address, default: UInt32(0))) ?? 0) != 0
    }

    public static func setMuted(_ id: AudioObjectID, _ muted: Bool, input: Bool = false) {
        let scope = input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
        let address = CAProperty.address(kAudioDevicePropertyMute, scope: scope)
        guard CAProperty.isSettable(id, address) else { return }
        try? CAProperty.set(id, address, UInt32(muted ? 1 : 0))
    }
}
