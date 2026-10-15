import CoreAudio
import Foundation

/// Fängt den Ton einer App ab (Process Tap), schaltet das Original stumm und spielt
/// ihn – mit eigener Lautstärke und Equalizer – über ein privates Aggregat-Gerät
/// auf dem gewünschten Ausgabegerät wieder ab.
public final class AppTap {
    public static let aggregateUIDPrefix = "local.private.mischpult.tap."

    public let processor: AudioProcessor
    public private(set) var processObjectIDs: [AudioObjectID]
    public let outputUID: String

    private let description: CATapDescription
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var sampleRateListener: CAListener?

    public init(name: String, processObjectIDs: [AudioObjectID], outputUID: String,
                gain: Float, eq: EQSettings) throws {
        self.processObjectIDs = processObjectIDs
        self.outputUID = outputUID

        let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        description.uuid = UUID()
        description.name = "Mischpult – \(name)"
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        self.description = description
        // Vorläufig; die echte Abtastrate kennt erst das Aggregat.
        processor = AudioProcessor(sampleRate: 48_000, gain: gain)

        do {
            try check(AudioHardwareCreateProcessTap(description, &tapID), "Tap anlegen")
            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Mischpult – \(name)",
                kAudioAggregateDeviceUIDKey: Self.aggregateUIDPrefix + UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                ]],
            ]
            try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID),
                      "Aggregat anlegen")
            processor.setEQ(eq, sampleRate: AudioDevices.nominalSampleRate(aggregateID))

            let processor = self.processor
            // Kein eigener Dispatch-Queue: der Block läuft direkt auf dem
            // Echtzeit-Thread von Core Audio (weniger Verzögerung, keine Aussetzer).
            try check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) {
                _, input, _, output, _ in
                processor.process(input: input, output: output)
            }, "Audio-Rückruf anlegen")
            disableDeviceInputs()
            try check(AudioDeviceStart(aggregateID, ioProcID), "Wiedergabe starten")
            // Wechselt das Gerät die Abtastrate, Equalizer und Glättung nachziehen.
            let deviceID = aggregateID
            sampleRateListener = CAListener(object: deviceID,
                                            address: CAProperty.address(kAudioDevicePropertyNominalSampleRate)) {
                [weak processor] in
                processor?.updateSampleRate(AudioDevices.nominalSampleRate(deviceID))
            }
        } catch {
            invalidate()
            throw error
        }
    }

    deinit { invalidate() }

    /// Das Aggregat enthält auch die Eingänge des Ausgabegeräts (bei AirPods das
    /// Mikrofon). Liefe es mit, schalteten Bluetooth-Kopfhörer in die schlechtere
    /// Headset-Qualität. Deshalb nur den Tap-Strom (er kommt zuletzt) verwenden.
    private func disableDeviceInputs() {
        let address = CAProperty.address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        let streams = (try? CAProperty.array(aggregateID, address, of: AudioObjectID.self, filler: 0)) ?? []
        let tapStreams = 1 // Stereo-Mixdown = genau ein Strom
        let deviceStreams = max(0, streams.count - tapStreams)
        processor.inputBufferOffset = deviceStreams
        guard deviceStreams > 0, let ioProcID else { return }

        let headerSize = MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mStreamIsOn) ?? 12
        let size = headerSize + MemoryLayout<UInt32>.size * streams.count
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer { raw.deallocate() }
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: size)
        let usage = raw.assumingMemoryBound(to: AudioHardwareIOProcStreamUsage.self)
        usage.pointee.mIOProc = unsafeBitCast(ioProcID, to: UnsafeMutableRawPointer.self)
        usage.pointee.mNumberStreams = UInt32(streams.count)
        let flags = (raw + headerSize).assumingMemoryBound(to: UInt32.self)
        for index in 0..<streams.count { flags[index] = index >= deviceStreams ? 1 : 0 }
        var propertyAddress = CAProperty.address(kAudioDevicePropertyIOProcStreamUsage,
                                                 scope: kAudioObjectPropertyScopeInput)
        AudioObjectSetPropertyData(aggregateID, &propertyAddress, 0, nil, UInt32(size), raw)
    }

    /// Neue Hilfsprozesse (z. B. ein weiterer Browser-Tab) in den laufenden Tap aufnehmen.
    public func update(processObjectIDs newIDs: [AudioObjectID]) throws {
        guard newIDs != processObjectIDs, tapID != kAudioObjectUnknown else { return }
        description.processes = newIDs
        var address = CAProperty.address(kAudioTapPropertyDescription)
        var reference = Unmanaged.passUnretained(description)
        try check(AudioObjectSetPropertyData(tapID, &address, 0, nil,
                                             UInt32(MemoryLayout<Unmanaged<CATapDescription>>.size),
                                             &reference), "Tap aktualisieren")
        processObjectIDs = newIDs
    }

    public func invalidate() {
        sampleRateListener = nil
        if aggregateID != kAudioObjectUnknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        ioProcID = nil
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }
}
