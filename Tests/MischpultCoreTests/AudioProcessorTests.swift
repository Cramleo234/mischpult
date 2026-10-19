import CoreAudio
import XCTest
@testable import MischpultCore

final class AudioProcessorTests: XCTestCase {
    /// Führt `processor` über Stereo-Eingang (interleaved) und gibt den Ausgang zurück.
    private func run(_ processor: AudioProcessor, input: [Float], inputChannels: UInt32 = 2,
                     outputChannels: UInt32 = 2, frames: Int) -> [Float] {
        var input = input
        var output = [Float](repeating: 99, count: frames * Int(outputChannels))
        input.withUnsafeMutableBytes { inBytes in
            output.withUnsafeMutableBytes { outBytes in
                var inList = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                    mNumberChannels: inputChannels, mDataByteSize: UInt32(inBytes.count), mData: inBytes.baseAddress))
                var outList = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                    mNumberChannels: outputChannels, mDataByteSize: UInt32(outBytes.count), mData: outBytes.baseAddress))
                processor.process(input: &inList, output: &outList)
            }
        }
        return output
    }

    func testUnityGainPassesSignalThrough() {
        let processor = AudioProcessor(sampleRate: 48_000)
        let input: [Float] = (0..<256).map { Float(sin(Double($0) * 0.1)) * 0.5 }
        let output = run(processor, input: input, frames: 128)
        XCTAssertEqual(output.count, input.count)
        for (a, b) in zip(input, output) { XCTAssertEqual(a, b, accuracy: 0.000_1) }
    }

    func testGainRampsSmoothlyToTarget() {
        let processor = AudioProcessor(sampleRate: 48_000, gain: 1)
        processor.setGain(0.5)
        let frames = 4_800 // 100 ms
        let output = run(processor, input: [Float](repeating: 0.4, count: frames * 2), frames: frames)
        // Kein Sprung am Anfang, am Ende angekommen.
        XCTAssertGreaterThan(output[0], 0.39)
        XCTAssertEqual(output[output.count - 1], 0.2, accuracy: 0.001)
        for index in stride(from: 2, to: output.count, by: 2) {
            XCTAssertLessThanOrEqual(output[index], output[index - 2] + 0.000_001)
        }
    }

    func testMuteSilencesAndOverwritesGarbage() {
        let processor = AudioProcessor(sampleRate: 48_000, gain: 0)
        let output = run(processor, input: [Float](repeating: 0.8, count: 512), frames: 256)
        XCTAssertTrue(output.allSatisfy { $0 == 0 })
    }

    func testBoostIsSoftClippedBelowOne() {
        let processor = AudioProcessor(sampleRate: 48_000, gain: 2)
        let output = run(processor, input: [Float](repeating: 0.9, count: 512), frames: 256)
        XCTAssertTrue(output.allSatisfy { $0 <= 1 && $0 > 0.95 })
        XCTAssertEqual(AudioProcessor.softClip(0.5), 0.5)
        XCTAssertEqual(AudioProcessor.softClip(-0.5), -0.5)
        XCTAssertLessThanOrEqual(abs(AudioProcessor.softClip(-10)), 1)
    }

    func testMonoInputFeedsBothSpeakersAndExtraChannelsStaySilent() {
        let processor = AudioProcessor(sampleRate: 48_000)
        let output = run(processor, input: [Float](repeating: 0.3, count: 64), inputChannels: 1,
                         outputChannels: 4, frames: 64)
        for frame in 0..<64 {
            XCTAssertEqual(output[frame * 4], 0.3, accuracy: 0.000_1)
            XCTAssertEqual(output[frame * 4 + 1], 0.3, accuracy: 0.000_1)
            XCTAssertEqual(output[frame * 4 + 2], 0)
            XCTAssertEqual(output[frame * 4 + 3], 0)
        }
    }

    func testPeakIsReportedAndReset() {
        let processor = AudioProcessor(sampleRate: 48_000)
        _ = run(processor, input: [Float](repeating: 0.25, count: 64), frames: 32)
        XCTAssertEqual(processor.takePeak(), 0.25, accuracy: 0.000_1)
        XCTAssertEqual(processor.takePeak(), 0)
    }

    func testBassBoostRaisesLowFrequencies() {
        let rate = 48_000.0
        let shelf = Biquad.lowShelf(frequency: 120, gainDB: 12, sampleRate: rate)
        XCTAssertEqual(20 * log10(shelf.magnitude(at: 20, sampleRate: rate)), 12, accuracy: 0.5)
        XCTAssertEqual(20 * log10(shelf.magnitude(at: 10_000, sampleRate: rate)), 0, accuracy: 0.2)
        let treble = Biquad.highShelf(frequency: 7_000, gainDB: -6, sampleRate: rate)
        XCTAssertEqual(20 * log10(treble.magnitude(at: 20_000, sampleRate: rate)), -6, accuracy: 0.6)
        XCTAssertEqual(20 * log10(treble.magnitude(at: 100, sampleRate: rate)), 0, accuracy: 0.2)
        let mid = Biquad.peaking(frequency: 1_200, gainDB: 6, q: 0.8, sampleRate: rate)
        XCTAssertEqual(20 * log10(mid.magnitude(at: 1_200, sampleRate: rate)), 6, accuracy: 0.05)
    }

    func testEQChangesSignalInProcessor() {
        let processor = AudioProcessor(sampleRate: 48_000)
        processor.setEQ(EQSettings(bass: 12))
        // 50-Hz-Sinus, eine Sekunde lang; letzte Hälfte (eingeschwungen) messen.
        let frames = 48_000
        let input: [Float] = (0..<frames).flatMap { frame -> [Float] in
            let value = Float(sin(2 * Double.pi * 50 * Double(frame) / 48_000)) * 0.1
            return [value, value]
        }
        let output = run(processor, input: input, frames: frames)
        let peak = output[frames...].map(abs).max() ?? 0
        XCTAssertGreaterThan(peak, 0.3) // ≈ +11 dB bei 50 Hz
    }

    func testDeviceInputBuffersBeforeTapAreIgnored() {
        let processor = AudioProcessor(sampleRate: 48_000)
        processor.inputBufferOffset = 1
        var microphone = [Float](repeating: 0.9, count: 32)
        var tap = [Float](repeating: 0.2, count: 64)
        var output = [Float](repeating: 0, count: 64)
        let list = AudioBufferList.allocate(maximumBuffers: 2)
        defer { free(list.unsafeMutablePointer) }
        microphone.withUnsafeMutableBytes { mic in
            tap.withUnsafeMutableBytes { tapBytes in
                output.withUnsafeMutableBytes { outBytes in
                    list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(mic.count), mData: mic.baseAddress)
                    list[1] = AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(tapBytes.count),
                                          mData: tapBytes.baseAddress)
                    var outList = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                        mNumberChannels: 2, mDataByteSize: UInt32(outBytes.count), mData: outBytes.baseAddress))
                    processor.process(input: list.unsafePointer, output: &outList)
                }
            }
        }
        XCTAssertTrue(output.allSatisfy { abs($0 - 0.2) < 0.000_1 })
    }

    func testUnityGainLeavesLoudSignalsUntouched() {
        let processor = AudioProcessor(sampleRate: 48_000)
        let input = [Float](repeating: 0.97, count: 128)
        let output = run(processor, input: input, frames: 64)
        XCTAssertTrue(output.allSatisfy { abs($0 - 0.97) < 0.000_1 })
    }

    func testMonoOutputMixesBothChannels() {
        let processor = AudioProcessor(sampleRate: 48_000)
        let input: [Float] = (0..<64).flatMap { _ in [Float(0.4), Float(0.2)] }
        let output = run(processor, input: input, outputChannels: 1, frames: 64)
        XCTAssertTrue(output.allSatisfy { abs($0 - 0.3) < 0.000_1 })
    }

    func testSampleRateChangeKeepsEQWorking() {
        let processor = AudioProcessor(sampleRate: 48_000)
        processor.setEQ(EQSettings(bass: 12))
        processor.updateSampleRate(44_100)
        XCTAssertEqual(processor.sampleRate, 44_100)
        let frames = 44_100
        let input: [Float] = (0..<frames).flatMap { frame -> [Float] in
            let value = Float(sin(2 * Double.pi * 50 * Double(frame) / 44_100)) * 0.1
            return [value, value]
        }
        let output = run(processor, input: input, frames: frames)
        XCTAssertGreaterThan(output[frames...].map(abs).max() ?? 0, 0.3)
    }

    func testAlertVolumeConversion() {
        XCTAssertEqual(AlertVolume.scriptValue(0.3), 30)
        XCTAssertEqual(AlertVolume.scriptValue(-1), 0)
        XCTAssertEqual(AlertVolume.scriptValue(2), 100)
        XCTAssertEqual(AlertVolume.fraction(fromScript: 45), 0.45, accuracy: 0.0001)
        XCTAssertEqual(AlertVolume.fraction(fromScript: 140), 1)
    }

    func testDefaultSettingsNeedNoTap() {
        var settings = AppSettings()
        XCTAssertFalse(settings.needsTap)
        settings.volume = 1.5
        XCTAssertTrue(settings.needsTap)
        settings = AppSettings()
        settings.muted = true
        XCTAssertTrue(settings.needsTap)
        XCTAssertEqual(settings.effectiveGain, 0)
        settings = AppSettings()
        settings.eq.treble = 3
        XCTAssertTrue(settings.needsTap)
    }
}
