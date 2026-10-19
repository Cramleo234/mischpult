import AudioToolbox
import CoreAudio
import Foundation

/// Fängt den Ton einer App ab (Process Tap), schaltet das Original stumm und spielt
/// ihn – mit eigener Lautstärke und Equalizer – auf dem gewünschten Ausgabegerät ab.
///
/// Zwei Wege:
/// - **Kombiniert** (Lautsprecher, Kabel …): Tap und Ausgabegerät stecken in einem
///   privaten Aggregat-Gerät; ein einziger Echtzeit-Rückruf liest und schreibt.
/// - **Getrennt** (Bluetooth-Kopfhörer): Das Aggregat enthält nur den Tap. Ausgegeben
///   wird über eine eigene Ausgabe-Einheit, deren Eingang (das Kopfhörer-Mikrofon)
///   abgeschaltet ist. So kann Mischpult die Kopfhörer nie in den Telefon-Modus
///   schalten. Klappt dieser Weg nicht, wird automatisch der kombinierte benutzt.
public final class AppTap {
    public enum Mode: String, Sendable { case combined, split }

    public static let aggregateUIDPrefix = "local.private.mischpult.tap."

    public let processor: AudioProcessor
    public private(set) var processObjectIDs: [AudioObjectID]
    public let outputUID: String
    public private(set) var mode: Mode = .combined

    private let description: CATapDescription
    private let name: String
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var sampleRateListener: CAListener?
    private var output: SplitOutput?

    /// Frames, die im getrennten Weg schon beim Abgriff ankamen (Kontrolle, ob er
    /// wirklich Ton liefert). Nur vom Echtzeit-Thread geschrieben.
    private let deliveredFrames: UnsafeMutablePointer<Int64> = {
        let pointer = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
        pointer.initialize(to: 0)
        return pointer
    }()
    public let createdAt = Date()

    /// Hat der getrennte Weg schon Ton geliefert?
    public var hasDeliveredAudio: Bool { deliveredFrames.pointee > 0 }

    /// - Parameter allowSplit: false erzwingt den kombinierten Weg (z. B. wenn der
    ///   getrennte auf diesem Gerät keinen Ton geliefert hat).
    public init(name: String, processObjectIDs: [AudioObjectID], outputUID: String,
                gain: Float, eq: EQSettings, allowSplit: Bool = true) throws {
        self.name = name
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
            let device = AudioDevices.deviceID(forUID: outputUID).flatMap(AudioDevices.device(for:))
            if allowSplit, let device, device.isBluetooth, device.hasInput {
                do {
                    try startSplit(outputDevice: device.id, eq: eq)
                    mode = .split
                } catch {
                    stopIO() // Bluetooth-Weg gescheitert: bewährten Weg versuchen
                    try startCombined(eq: eq)
                }
            } else {
                try startCombined(eq: eq)
            }
            // Wechselt die Abtastrate, Equalizer, Glättung und Ausgabe nachziehen.
            let deviceID = aggregateID
            sampleRateListener = CAListener(object: deviceID,
                                            address: CAProperty.address(kAudioDevicePropertyNominalSampleRate)) {
                [weak self] in
                let rate = AudioDevices.nominalSampleRate(deviceID)
                self?.processor.updateSampleRate(rate)
                try? self?.output?.reconfigure(sampleRate: rate)
            }
        } catch {
            invalidate()
            throw error
        }
    }

    deinit {
        invalidate()
        deliveredFrames.deallocate()
    }

    // MARK: Kombinierter Weg

    private func startCombined(eq: EQSettings) throws {
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
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID), "Aggregat anlegen")
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
    }

    /// Im kombinierten Weg enthält das Aggregat auch die Eingänge des Ausgabegeräts.
    /// Nur den Tap-Strom (er kommt zuletzt) verwenden.
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

    // MARK: Getrennter Weg (Bluetooth)

    private func startSplit(outputDevice: AudioObjectID, eq: EQSettings) throws {
        // Aggregat nur mit dem Tap – ohne Kopfhörer, also ohne deren Mikrofon.
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Mischpult – \(name)",
            kAudioAggregateDeviceUIDKey: Self.aggregateUIDPrefix + UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: false,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID), "Aggregat anlegen")
        let rate = AudioDevices.nominalSampleRate(aggregateID)
        processor.setEQ(eq, sampleRate: rate)
        processor.inputBufferOffset = 0

        let output = try SplitOutput(device: outputDevice, sampleRate: rate)
        self.output = output
        let processor = self.processor
        let ring = output.ring
        let scratch = output.scratch
        let delivered = deliveredFrames
        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) {
            _, input, _, _, _ in
            // Tap-Ton verarbeiten und in den Ringpuffer für die Ausgabe legen.
            let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let first = list.first, first.mNumberChannels > 0 else { return }
            let frames = min(Int(first.mDataByteSize) / (4 * Int(first.mNumberChannels)), scratch.frameCapacity)
            guard frames > 0 else { return }
            scratch.list.pointee.mBuffers.mDataByteSize = UInt32(frames * AudioRingBuffer.channels * 4)
            processor.process(input: input, output: scratch.list)
            ring.write(scratch.samples, frames: frames)
            delivered.pointee &+= Int64(frames)
        }, "Audio-Rückruf anlegen")
        try check(AudioDeviceStart(aggregateID, ioProcID), "Abgriff starten")
        try output.start()
    }

    // MARK: Pflege

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

    private func stopIO() {
        output?.stop()
        output = nil
        if aggregateID != kAudioObjectUnknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        ioProcID = nil
    }

    public func invalidate() {
        sampleRateListener = nil
        stopIO()
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }
}

/// Zwischenpuffer für einen Echtzeit-Rückruf (einmal reserviert).
final class ScratchBuffer {
    let frameCapacity: Int
    let samples: UnsafeMutablePointer<Float>
    let list: UnsafeMutablePointer<AudioBufferList>

    init(frameCapacity: Int) {
        self.frameCapacity = frameCapacity
        samples = .allocate(capacity: frameCapacity * AudioRingBuffer.channels)
        samples.initialize(repeating: 0, count: frameCapacity * AudioRingBuffer.channels)
        list = .allocate(capacity: 1)
        list.initialize(to: AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
            mNumberChannels: UInt32(AudioRingBuffer.channels),
            mDataByteSize: UInt32(frameCapacity * AudioRingBuffer.channels * 4),
            mData: UnsafeMutableRawPointer(samples))))
    }

    deinit {
        samples.deallocate()
        list.deallocate()
    }
}

/// Reine Ausgabe auf ein Gerät (AUHAL) – Eingang ausdrücklich abgeschaltet.
/// Liest den verarbeiteten Ton aus dem Ringpuffer; macOS rechnet bei Bedarf
/// die Abtastrate auf die des Geräts um.
final class SplitOutput {
    let ring = AudioRingBuffer(capacity: 16_384, targetFill: 1_024)
    let scratch = ScratchBuffer(frameCapacity: 8_192)
    private var unit: AudioUnit?

    init(device: AudioObjectID, sampleRate: Double) throws {
        var component = AudioComponentDescription(componentType: kAudioUnitType_Output,
                                                  componentSubType: kAudioUnitSubType_HALOutput,
                                                  componentManufacturer: kAudioUnitManufacturer_Apple,
                                                  componentFlags: 0, componentFlagsMask: 0)
        guard let found = AudioComponentFindNext(nil, &component) else {
            throw CoreAudioError("Ausgabe-Einheit finden", -1)
        }
        var created: AudioUnit?
        try check(AudioComponentInstanceNew(found, &created), "Ausgabe-Einheit anlegen")
        guard let unit = created else { throw CoreAudioError("Ausgabe-Einheit anlegen", -1) }
        self.unit = unit

        // Eingang (Element 1) aus, Ausgang (Element 0) an: das Mikrofon bleibt zu.
        var off: UInt32 = 0
        var on: UInt32 = 1
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1,
                                       &off, UInt32(MemoryLayout<UInt32>.size)), "Eingang abschalten")
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0,
                                       &on, UInt32(MemoryLayout<UInt32>.size)), "Ausgang einschalten")
        var deviceID = device
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                       &deviceID, UInt32(MemoryLayout<AudioObjectID>.size)), "Gerät wählen")
        try setFormat(sampleRate: sampleRate)

        var callback = AURenderCallbackStruct(inputProc: { refCon, _, _, _, frames, data in
            let output = Unmanaged<SplitOutput>.fromOpaque(refCon).takeUnretainedValue()
            guard let data, let buffer = UnsafeMutableAudioBufferListPointer(data).first,
                  let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            // Nie mehr schreiben, als der Ausgabepuffer fasst.
            let fit = Int(buffer.mDataByteSize) / (AudioRingBuffer.channels * MemoryLayout<Float>.size)
            output.ring.read(into: samples, frames: min(Int(frames), fit))
            return noErr
        }, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        try check(AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0,
                                       &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)),
                  "Ausgabe-Rückruf setzen")
        try check(AudioUnitInitialize(unit), "Ausgabe-Einheit vorbereiten")
    }

    deinit { stop() }

    /// Interleaved Stereo-Float in der Abtastrate des Abgriffs.
    private func setFormat(sampleRate: Double) throws {
        guard let unit else { return }
        var format = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(AudioRingBuffer.channels * 4), mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(AudioRingBuffer.channels * 4),
            mChannelsPerFrame: UInt32(AudioRingBuffer.channels), mBitsPerChannel: 32, mReserved: 0)
        try check(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0,
                                       &format, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)),
                  "Ausgabeformat setzen")
    }

    func start() throws {
        guard let unit else { return }
        try check(AudioOutputUnitStart(unit), "Ausgabe starten")
    }

    /// Neue Abtastrate des Abgriffs: Ausgabe kurz anhalten und neu einstellen.
    func reconfigure(sampleRate: Double) throws {
        guard let unit else { return }
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        // Kein ring.reset(): Der Abgriff schreibt weiter; der Puffer gleicht selbst aus.
        try setFormat(sampleRate: sampleRate)
        try check(AudioUnitInitialize(unit), "Ausgabe-Einheit vorbereiten")
        try check(AudioOutputUnitStart(unit), "Ausgabe starten")
    }

    func stop() {
        guard let unit else { return }
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
        self.unit = nil
    }
}
