import Foundation
import MischpultAtomics

/// Ringpuffer für Stereo-Ton zwischen genau einem schreibenden und einem lesenden
/// Echtzeit-Thread. Ohne Sperren und ohne Speicherreservierung im Betrieb.
///
/// Der Leser gleicht kleine Taktunterschiede aus: Läuft der Puffer zu voll, springt
/// er auf die Ziel-Füllung vor; läuft er leer, gibt er Stille aus und wartet, bis
/// wieder genug Ton vorliegt.
public final class AudioRingBuffer {
    public static let channels = 2
    public let capacity: Int
    /// Ziel-Füllung in Frames (Verzögerung zwischen Abgriff und Ausgabe).
    public let targetFill: Int

    private let storage: UnsafeMutablePointer<Float>
    private let writeIndex: UnsafeMutablePointer<Int64>
    private let readIndex: UnsafeMutablePointer<Int64>
    private var priming = true // nur Leser

    public init(capacity: Int = 16_384, targetFill: Int = 1_024) {
        self.capacity = capacity
        self.targetFill = targetFill
        storage = .allocate(capacity: capacity * Self.channels)
        storage.initialize(repeating: 0, count: capacity * Self.channels)
        writeIndex = .allocate(capacity: 1)
        writeIndex.initialize(to: 0)
        readIndex = .allocate(capacity: 1)
        readIndex.initialize(to: 0)
    }

    deinit {
        storage.deallocate()
        writeIndex.deallocate()
        readIndex.deallocate()
    }

    /// Frames, die gerade zum Lesen bereitliegen.
    public var available: Int {
        Int(mp_load_acquire(writeIndex) - mp_load_acquire(readIndex))
    }

    /// Schreibt interleaved Stereo-Frames. Was nicht mehr passt, wird verworfen.
    @discardableResult
    public func write(_ source: UnsafePointer<Float>, frames: Int) -> Int {
        let write = mp_load_acquire(writeIndex)
        let read = mp_load_acquire(readIndex)
        // Unsinnige Stände (z. B. kurz nach einem Zurücksetzen) nie überschreiten lassen.
        let used = min(max(Int(write - read), 0), capacity)
        let free = capacity - used
        let count = min(frames, max(free, 0))
        guard count > 0 else { return 0 }
        let start = Int(write % Int64(capacity))
        let first = min(count, capacity - start)
        (storage + start * Self.channels).update(from: source, count: first * Self.channels)
        if count > first {
            storage.update(from: source + first * Self.channels, count: (count - first) * Self.channels)
        }
        mp_store_release(writeIndex, write + Int64(count))
        return count
    }

    /// Liest interleaved Stereo-Frames; fehlende Frames werden mit Stille gefüllt.
    /// Gibt die Zahl der echten (nicht stillen) Frames zurück.
    @discardableResult
    public func read(into destination: UnsafeMutablePointer<Float>, frames: Int) -> Int {
        var read = mp_load_acquire(readIndex)
        let write = mp_load_acquire(writeIndex)
        var filled = Int(write - read)
        if filled < 0 || filled > capacity {
            read = write
            filled = 0
        }
        // Zu viel Vorlauf (Taktabweichung): auf die Ziel-Füllung vorspringen.
        if filled > targetFill * 4 {
            read = write - Int64(targetFill)
            filled = targetFill
        }
        if priming {
            guard filled >= targetFill else {
                destination.update(repeating: 0, count: frames * Self.channels)
                mp_store_release(readIndex, read)
                return 0
            }
            priming = false
        }
        let count = min(frames, filled)
        let start = Int(read % Int64(capacity))
        let first = min(count, capacity - start)
        destination.update(from: storage + start * Self.channels, count: first * Self.channels)
        if count > first {
            (destination + first * Self.channels).update(from: storage, count: (count - first) * Self.channels)
        }
        if count < frames {
            (destination + count * Self.channels).update(repeating: 0, count: (frames - count) * Self.channels)
            priming = true // leergelaufen: erst wieder auffüllen
        }
        mp_store_release(readIndex, read + Int64(count))
        return count
    }

    /// Nur aufrufen, während weder gelesen noch geschrieben wird.
    public func reset() {
        mp_store_release(writeIndex, 0)
        mp_store_release(readIndex, 0)
        priming = true
    }
}
