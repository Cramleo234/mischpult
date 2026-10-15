import CoreAudio
import Foundation

/// Fehler einer Core-Audio-Funktion mit ihrem OSStatus.
public struct CoreAudioError: Error, CustomStringConvertible {
    public let operation: String
    public let status: OSStatus

    public init(_ operation: String, _ status: OSStatus) {
        self.operation = operation
        self.status = status
    }

    public var description: String {
        let code = UInt32(bitPattern: status)
        let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xFF) }
        let fourCC = bytes.allSatisfy { $0 >= 32 && $0 < 127 } ? " '\(String(decoding: bytes, as: UTF8.self))'" : ""
        return "\(operation) fehlgeschlagen (\(status)\(fourCC))"
    }
}

@inline(__always)
func check(_ status: OSStatus, _ operation: @autoclosure () -> String) throws {
    guard status == noErr else { throw CoreAudioError(operation(), status) }
}

/// Kleine Hilfen, um Eigenschaften von Core-Audio-Objekten zu lesen und zu setzen.
public enum CAProperty {
    public static func address(_ selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                               element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    public static func has(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        return AudioObjectHasProperty(object, &address)
    }

    public static func isSettable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(object, &address),
              AudioObjectIsPropertySettable(object, &address, &settable) == noErr else { return false }
        return settable.boolValue
    }

    public static func value<T: BitwiseCopyable>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress,
                                default defaultValue: T) throws -> T {
        var address = address
        var value = defaultValue
        var size = UInt32(MemoryLayout<T>.size)
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value),
                  "Eigenschaft lesen")
        return value
    }

    public static func array<T: BitwiseCopyable>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress,
                                of _: T.Type, filler: T) throws -> [T] {
        var address = address
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size), "Größe lesen")
        let count = Int(size) / MemoryLayout<T>.stride
        guard count > 0 else { return [] }
        var values = [T](repeating: filler, count: count)
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &values), "Liste lesen")
        return Array(values.prefix(Int(size) / MemoryLayout<T>.stride))
    }

    public static func string(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> String? {
        var address = address
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    public static func set<T: BitwiseCopyable>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: T) throws {
        var address = address
        var value = value
        try check(AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value),
                  "Eigenschaft setzen")
    }
}

/// Hält einen Property-Listener am Leben und meldet ihn beim Freigeben wieder ab.
public final class CAListener {
    private let object: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock
    private let queue: DispatchQueue

    public init?(object: AudioObjectID, address: AudioObjectPropertyAddress,
                 queue: DispatchQueue = .main, handler: @escaping () -> Void) {
        self.object = object
        self.address = address
        self.queue = queue
        self.block = { _, _ in handler() }
        guard AudioObjectAddPropertyListenerBlock(object, &self.address, queue, block) == noErr else { return nil }
    }

    deinit {
        AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
    }
}
