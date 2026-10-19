import AppKit
import CoreAudio
import Darwin

/// Ein Prozess, den Core Audio als Audio-Client kennt.
public struct AudioProcess: Hashable, Sendable {
    public let objectID: AudioObjectID
    public let pid: pid_t
    public let bundleID: String?
    public let isRunningOutput: Bool
    /// Nimmt der Prozess gerade auf (Mikrofon)?
    public var isRunningInput = false
    /// Geräte, von denen der Prozess gerade aufnimmt.
    public var inputDeviceIDs: [AudioObjectID] = []

    public init(objectID: AudioObjectID, pid: pid_t, bundleID: String?, isRunningOutput: Bool,
                isRunningInput: Bool = false, inputDeviceIDs: [AudioObjectID] = []) {
        self.objectID = objectID
        self.pid = pid
        self.bundleID = bundleID
        self.isRunningOutput = isRunningOutput
        self.isRunningInput = isRunningInput
        self.inputDeviceIDs = inputDeviceIDs
    }
}

/// Alle Audio-Prozesse einer App (z. B. Safari plus seine Web-Inhalt-Prozesse).
public struct AudioAppGroup: Identifiable, Sendable {
    /// Bundle-ID der App oder „pid:<nummer>“ ohne Bundle.
    public let id: String
    public let name: String
    public let bundleID: String?
    public let appPID: pid_t
    public let isRegularApp: Bool
    public let processes: [AudioProcess]

    public var processObjectIDs: [AudioObjectID] { processes.map(\.objectID).sorted() }
    public var isPlaying: Bool { processes.contains(where: \.isRunningOutput) }
}

public enum AudioProcesses {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    public static func list() -> [AudioProcess] {
        let ids = (try? CAProperty.array(system, CAProperty.address(kAudioHardwarePropertyProcessObjectList),
                                         of: AudioObjectID.self, filler: 0)) ?? []
        return ids.compactMap { id in
            guard let pid = try? CAProperty.value(id, CAProperty.address(kAudioProcessPropertyPID),
                                                  default: pid_t(-1)), pid > 0 else { return nil }
            let bundle = CAProperty.string(id, CAProperty.address(kAudioProcessPropertyBundleID))
            let running = (try? CAProperty.value(id, CAProperty.address(kAudioProcessPropertyIsRunningOutput),
                                                 default: UInt32(0))) ?? 0
            let recording = (try? CAProperty.value(id, CAProperty.address(kAudioProcessPropertyIsRunningInput),
                                                   default: UInt32(0))) ?? 0
            let inputDevices = recording != 0
                ? (try? CAProperty.array(id, CAProperty.address(kAudioProcessPropertyDevices,
                                                                scope: kAudioObjectPropertyScopeInput),
                                         of: AudioObjectID.self, filler: 0)) ?? []
                : []
            return AudioProcess(objectID: id, pid: pid, bundleID: bundle?.isEmpty == false ? bundle : nil,
                                isRunningOutput: running != 0, isRunningInput: recording != 0,
                                inputDeviceIDs: inputDevices)
        }
    }

    /// Fasst Hilfsprozesse unter der App zusammen, die für sie verantwortlich ist.
    public static func groups(excluding ownPID: pid_t = getpid()) -> [AudioAppGroup] {
        var buckets: [String: (owner: Owner, processes: [AudioProcess])] = [:]
        for process in list() where process.pid != ownPID {
            let owner = Owner.resolve(process)
            if owner.pid == ownPID { continue }
            buckets[owner.key, default: (owner, [])].processes.append(process)
        }
        return buckets.map { key, value in
            AudioAppGroup(id: key, name: value.owner.name, bundleID: value.owner.bundleID,
                          appPID: value.owner.pid, isRegularApp: value.owner.isRegular,
                          processes: value.processes)
        }
    }

    // MARK: Zuordnung Hilfsprozess → App

    struct Owner {
        let key: String
        let name: String
        let bundleID: String?
        let pid: pid_t
        let isRegular: Bool

        static func resolve(_ process: AudioProcess) -> Owner {
            let responsible = responsiblePID(for: process.pid)
            for pid in [responsible, process.pid] {
                if let app = NSRunningApplication(processIdentifier: pid),
                   app.activationPolicy == .regular || pid == responsible && pid != process.pid {
                    let bundle = app.bundleIdentifier
                    return Owner(key: bundle ?? "pid:\(pid)",
                                 name: app.localizedName ?? bundle ?? processName(pid),
                                 bundleID: bundle, pid: pid, isRegular: app.activationPolicy == .regular)
                }
            }
            // Hilfsprozesse ohne verantwortliche App: Bundle-ID kürzen
            // („com.google.Chrome.helper“ → „com.google.Chrome“).
            if let bundle = process.bundleID {
                if let parent = NSWorkspace.shared.runningApplications.first(where: {
                    guard let id = $0.bundleIdentifier, $0.activationPolicy == .regular else { return false }
                    return bundle.hasPrefix(id + ".")
                }), let id = parent.bundleIdentifier {
                    return Owner(key: id, name: parent.localizedName ?? id, bundleID: id,
                                 pid: parent.processIdentifier, isRegular: true)
                }
                return Owner(key: bundle, name: readableName(bundle: bundle, pid: process.pid),
                             bundleID: bundle, pid: process.pid, isRegular: false)
            }
            return Owner(key: "pid:\(process.pid)", name: processName(process.pid),
                         bundleID: nil, pid: process.pid, isRegular: false)
        }
    }

    private typealias ResponsibleFunction = @convention(c) (pid_t) -> pid_t
    private static let responsibleFunction: ResponsibleFunction? = {
        // Nicht öffentliche, aber seit Jahren stabile Funktion von libquarantine/libsystem.
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                                 "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: ResponsibleFunction.self)
    }()

    public static func responsiblePID(for pid: pid_t) -> pid_t {
        guard let function = responsibleFunction else { return pid }
        let result = function(pid)
        return result > 0 ? result : pid
    }

    static func processName(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : "PID \(pid)"
    }

    static func readableName(bundle: String, pid: pid_t) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle),
           let name = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String {
            return name
        }
        let name = processName(pid)
        return name.hasPrefix("PID ") ? (bundle.split(separator: ".").last.map(String.init) ?? bundle) : name
    }
}
