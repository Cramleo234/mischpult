import CoreAudio
import XCTest
@testable import MischpultCore

final class AudioRingBufferTests: XCTestCase {
    private func frames(_ values: [Float]) -> [Float] { values.flatMap { [$0, $0] } }

    private func read(_ ring: AudioRingBuffer, _ count: Int) -> [Float] {
        var out = [Float](repeating: 99, count: count * 2)
        out.withUnsafeMutableBufferPointer { _ = ring.read(into: $0.baseAddress!, frames: count) }
        return stride(from: 0, to: out.count, by: 2).map { out[$0] }
    }

    func testWaitsForTargetFillThenKeepsOrder() {
        let ring = AudioRingBuffer(capacity: 64, targetFill: 4)
        frames([1, 2, 3]).withUnsafeBufferPointer { _ = ring.write($0.baseAddress!, frames: 3) }
        XCTAssertEqual(read(ring, 2), [0, 0]) // noch nicht genug Vorlauf → Stille
        frames([4, 5]).withUnsafeBufferPointer { _ = ring.write($0.baseAddress!, frames: 2) }
        XCTAssertEqual(read(ring, 3), [1, 2, 3])
        XCTAssertEqual(read(ring, 2), [4, 5])
    }

    func testWrapsAroundTheEnd() {
        let ring = AudioRingBuffer(capacity: 8, targetFill: 2) // 5 Frames < 4 × Ziel: kein Vorspringen
        for start in stride(from: 0, to: 40, by: 5) {
            let values = (start..<start + 5).map(Float.init)
            frames(values).withUnsafeBufferPointer { _ = ring.write($0.baseAddress!, frames: 5) }
            XCTAssertEqual(read(ring, 5), values)
        }
    }

    func testUnderrunGivesSilenceAndPrimesAgain() {
        let ring = AudioRingBuffer(capacity: 32, targetFill: 2)
        frames([1, 2]).withUnsafeBufferPointer { _ = ring.write($0.baseAddress!, frames: 2) }
        XCTAssertEqual(read(ring, 4), [1, 2, 0, 0])
        frames([3]).withUnsafeBufferPointer { _ = ring.write($0.baseAddress!, frames: 1) }
        XCTAssertEqual(read(ring, 1), [0]) // wartet wieder auf 2 Frames Vorlauf
    }

    func testDropsWhenFullAndSkipsAheadOnDrift() {
        let ring = AudioRingBuffer(capacity: 16, targetFill: 2)
        let values = (0..<20).map(Float.init)
        let written = frames(values).withUnsafeBufferPointer { ring.write($0.baseAddress!, frames: 20) }
        XCTAssertEqual(written, 16) // Rest verworfen
        // 16 > 4 × Ziel → auf die neuesten 2 Frames vorspringen
        XCTAssertEqual(read(ring, 2), [14, 15])
    }
}
