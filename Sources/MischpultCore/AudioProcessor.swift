import CoreAudio
import Foundation

/// Equalizer-Einstellung in Dezibel (−12 … +12).
public struct EQSettings: Codable, Equatable, Sendable {
    public var bass: Float
    public var mid: Float
    public var treble: Float

    public init(bass: Float = 0, mid: Float = 0, treble: Float = 0) {
        self.bass = bass
        self.mid = mid
        self.treble = treble
    }

    public static let flat = EQSettings()
    public static let range: ClosedRange<Float> = -12...12
    public var isFlat: Bool { abs(bass) < 0.05 && abs(mid) < 0.05 && abs(treble) < 0.05 }
}

/// Koeffizienten eines Biquad-Filters (RBJ-Kochbuch, normiert auf a0 = 1).
public struct Biquad: Equatable, Sendable {
    public var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0

    public static let identity = Biquad()

    public static func lowShelf(frequency: Double, gainDB: Float, sampleRate: Double) -> Biquad {
        shelf(frequency: frequency, gainDB: gainDB, sampleRate: sampleRate, high: false)
    }

    public static func highShelf(frequency: Double, gainDB: Float, sampleRate: Double) -> Biquad {
        shelf(frequency: frequency, gainDB: gainDB, sampleRate: sampleRate, high: true)
    }

    private static func shelf(frequency: Double, gainDB: Float, sampleRate: Double, high: Bool) -> Biquad {
        guard abs(gainDB) > 0.01 else { return .identity }
        let a = pow(10, Double(gainDB) / 40)
        let w0 = 2 * Double.pi * frequency / sampleRate
        let cosW = cos(w0)
        let alpha = sin(w0) / 2 * sqrt(2) // Flankensteilheit S = 1
        let root = 2 * sqrt(a) * alpha
        let sign: Double = high ? -1 : 1
        let b0 = a * ((a + 1) - sign * (a - 1) * cosW + root)
        let b1 = sign * 2 * a * ((a - 1) - sign * (a + 1) * cosW)
        let b2 = a * ((a + 1) - sign * (a - 1) * cosW - root)
        let a0 = (a + 1) + sign * (a - 1) * cosW + root
        let a1 = -sign * 2 * ((a - 1) + sign * (a + 1) * cosW)
        let a2 = (a + 1) + sign * (a - 1) * cosW - root
        return Biquad(b0: Float(b0 / a0), b1: Float(b1 / a0), b2: Float(b2 / a0),
                      a1: Float(a1 / a0), a2: Float(a2 / a0))
    }

    public static func peaking(frequency: Double, gainDB: Float, q: Double, sampleRate: Double) -> Biquad {
        guard abs(gainDB) > 0.01 else { return .identity }
        let a = pow(10, Double(gainDB) / 40)
        let w0 = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(w0) / (2 * q)
        let cosW = cos(w0)
        let a0 = 1 + alpha / a
        return Biquad(b0: Float((1 + alpha * a) / a0), b1: Float(-2 * cosW / a0),
                      b2: Float((1 - alpha * a) / a0), a1: Float(-2 * cosW / a0),
                      a2: Float((1 - alpha / a) / a0))
    }

    /// Betrag des Frequenzgangs bei `frequency` (für Tests).
    public func magnitude(at frequency: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        func complex(_ c0: Float, _ c1: Float, _ c2: Float) -> (Double, Double) {
            (Double(c0) + Double(c1) * cos(w) + Double(c2) * cos(2 * w),
             -Double(c1) * sin(w) - Double(c2) * sin(2 * w))
        }
        let num = complex(b0, b1, b2)
        let den = complex(1, a1, a2)
        return sqrt(num.0 * num.0 + num.1 * num.1) / sqrt(den.0 * den.0 + den.1 * den.1)
    }
}

/// Echtzeit-Verarbeitung für eine App: Lautstärke (mit Boost), Equalizer, Pegelanzeige.
///
/// Der Haupt-Thread schreibt nur `Controls`, der Audio-Thread liest sie. Im
/// Audio-Thread wird nichts reserviert und nichts gesperrt.
public final class AudioProcessor {
    public static let maxChannels = 16
    static let bands = 3

    struct Controls {
        var targetGain: Float = 1
        var generation: UInt32 = 0
        var eqActive: Bool = false
        var coefficients: (Biquad, Biquad, Biquad) = (.identity, .identity, .identity)
        var peak: Float = 0
    }

    private let controls: UnsafeMutablePointer<Controls>
    // Nur vom Audio-Thread benutzt:
    private var gain: Float
    private var seenGeneration: UInt32 = .max
    private var eqActive = false
    private let coefficients: UnsafeMutablePointer<Biquad>
    private let filterState: UnsafeMutablePointer<Float> // [Kanal][Band][z1, z2]
    private let inputs: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>
    private let inputStrides: UnsafeMutablePointer<Int>
    private let outputs: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>
    private let outputStrides: UnsafeMutablePointer<Int>
    public private(set) var sampleRate: Double
    /// Puffer davor gehören zu Eingängen des Ausgabegeräts (z. B. Kopfhörer-Mikrofon)
    /// und werden ignoriert; der Ton der App steckt im Tap-Puffer dahinter.
    public var inputBufferOffset = 0

    public init(sampleRate: Double, gain: Float = 1) {
        self.sampleRate = sampleRate
        self.gain = gain
        controls = .allocate(capacity: 1)
        controls.initialize(to: Controls(targetGain: gain))
        coefficients = .allocate(capacity: Self.bands)
        coefficients.initialize(repeating: .identity, count: Self.bands)
        filterState = .allocate(capacity: Self.maxChannels * Self.bands * 2)
        filterState.initialize(repeating: 0, count: Self.maxChannels * Self.bands * 2)
        inputs = .allocate(capacity: Self.maxChannels)
        inputs.initialize(repeating: nil, count: Self.maxChannels)
        inputStrides = .allocate(capacity: Self.maxChannels)
        inputStrides.initialize(repeating: 1, count: Self.maxChannels)
        outputs = .allocate(capacity: Self.maxChannels)
        outputs.initialize(repeating: nil, count: Self.maxChannels)
        outputStrides = .allocate(capacity: Self.maxChannels)
        outputStrides.initialize(repeating: 1, count: Self.maxChannels)
    }

    deinit {
        controls.deallocate()
        coefficients.deallocate()
        filterState.deallocate()
        inputs.deallocate()
        inputStrides.deallocate()
        outputs.deallocate()
        outputStrides.deallocate()
    }

    // MARK: Steuerung (Haupt-Thread)

    /// Lautstärke 0 … 2 (2 = +6 dB Boost). Stumm = 0.
    public func setGain(_ value: Float) {
        controls.pointee.targetGain = min(max(value, 0), 4)
    }

    public func setEQ(_ eq: EQSettings) {
        setEQ(eq, sampleRate: sampleRate)
    }

    public func setEQ(_ eq: EQSettings, sampleRate: Double) {
        self.sampleRate = sampleRate
        controls.pointee.coefficients = (
            .lowShelf(frequency: 120, gainDB: eq.bass, sampleRate: sampleRate),
            .peaking(frequency: 1_200, gainDB: eq.mid, q: 0.8, sampleRate: sampleRate),
            .highShelf(frequency: 7_000, gainDB: eq.treble, sampleRate: sampleRate)
        )
        controls.pointee.eqActive = !eq.isFlat
        controls.pointee.generation &+= 1
    }

    /// Höchster Pegel seit dem letzten Abruf (0 … 1+).
    public func takePeak() -> Float {
        let value = controls.pointee.peak
        controls.pointee.peak = 0
        return value
    }

    // MARK: Verarbeitung (Audio-Thread)

    /// Zerlegt eine Pufferliste in einzelne Kanäle (interleaved oder getrennt).
    @inline(__always)
    private func split(_ list: UnsafeMutableAudioBufferListPointer, skipping skip: Int = 0,
                       into channels: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>,
                       strides: UnsafeMutablePointer<Int>, frames: inout Int) -> Int {
        var count = 0
        for index in min(skip, list.count)..<list.count {
            let buffer = list[index]
            let channelCount = Int(buffer.mNumberChannels)
            guard channelCount > 0, let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            frames = min(frames, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channelCount))
            for channel in 0..<channelCount where count < Self.maxChannels {
                channels[count] = data + channel
                strides[count] = channelCount
                count += 1
            }
        }
        return count
    }

    /// Kopiert die App-Tonspur in den Ausgang und wendet dabei alle Regler an.
    public func process(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        let outputList = UnsafeMutableAudioBufferListPointer(output)
        // Ausgang zuerst stumm schalten, damit nie alter Speicherinhalt hörbar wird.
        for buffer in outputList {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        var frames = Int.max
        let inputList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let inputCount = split(inputList, skipping: inputBufferOffset, into: inputs, strides: inputStrides, frames: &frames)
        let outputCount = split(outputList, into: outputs, strides: outputStrides, frames: &frames)
        guard inputCount > 0, outputCount > 0, frames > 0, frames != .max else { return }

        let state = controls.pointee
        if state.generation != seenGeneration {
            seenGeneration = state.generation
            coefficients[0] = state.coefficients.0
            coefficients[1] = state.coefficients.1
            coefficients[2] = state.coefficients.2
            if state.eqActive != eqActive || !state.eqActive {
                filterState.update(repeating: 0, count: Self.maxChannels * Self.bands * 2)
            }
            eqActive = state.eqActive
        }
        let target = state.targetGain
        // Sanftes Angleichen (~10 ms) verhindert Knackser beim Schieben.
        let smoothing: Float = 1 - exp(-1 / Float(sampleRate * 0.01))
        // Nur Stereo-Mixdown: zusätzliche Ausgangskanäle (z. B. 5.1) bleiben still.
        let usedOutputs = min(outputCount, max(inputCount, 2))
        var peak = controls.pointee.peak
        var currentGain = gain

        for frame in 0..<frames {
            currentGain += (target - currentGain) * smoothing
            if abs(currentGain - target) < 0.000_01 { currentGain = target }
            for channel in 0..<usedOutputs {
                let source = channel < inputCount ? channel : 0
                var sample = inputs[source]![frame * inputStrides[source]]
                if eqActive {
                    for band in 0..<Self.bands {
                        let c = coefficients[band]
                        let z = filterState + (channel * Self.bands + band) * 2
                        let y = c.b0 * sample + z[0]
                        z[0] = c.b1 * sample - c.a1 * y + z[1]
                        z[1] = c.b2 * sample - c.a2 * y
                        sample = y
                    }
                }
                sample *= currentGain
                sample = Self.softClip(sample)
                outputs[channel]![frame * outputStrides[channel]] = sample
                let level = abs(sample)
                if level > peak { peak = level }
            }
        }
        gain = currentGain
        controls.pointee.peak = peak
    }

    /// Lässt alles unter 0,9 unverändert und rundet darüber weich auf höchstens 1 ab.
    @inline(__always)
    static func softClip(_ x: Float) -> Float {
        let magnitude = abs(x)
        guard magnitude > 0.9 else { return x }
        let shaped = 0.9 + 0.1 * tanh((magnitude - 0.9) / 0.1)
        return x < 0 ? -shaped : shaped
    }
}
