import AppKit
import CoreAudio
import Darwin

/// An app with sound going through CoreAudio. Helpers that play on an app's behalf (a
/// browser's audio process) count as the app.
struct AudioApp: Identifiable, Equatable {
    /// The app's process.
    let pid: pid_t
    /// What its settings are saved under: the bundle identifier, else the name.
    let key: String
    let name: String
    let bundleID: String?
    /// Its audio process objects, the app's own and its helpers'.
    var objects: [AudioObjectID]
    /// Playing sound right now.
    var isPlaying: Bool

    var id: pid_t { pid }
}

@available(macOS 14.4, *)
enum AudioApps {
    /// Every regular app with an audio connection, PasteRing aside.
    static func current() -> [AudioApp] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var apps: [pid_t: AudioApp] = [:]
        for object in processObjects() {
            var pid: pid_t = -1
            guard AudioSystem.read(object, kAudioProcessPropertyPID, into: &pid), pid > 0, pid != ownPID,
                  let owner = regularApp(owning: pid), owner.processIdentifier != ownPID
            else { continue }
            var running: UInt32 = 0
            AudioSystem.read(object, kAudioProcessPropertyIsRunningOutput, into: &running)
            let ownerPID = owner.processIdentifier
            if apps[ownerPID] == nil {
                let name = owner.localizedName ?? owner.bundleIdentifier ?? "\(ownerPID)"
                apps[ownerPID] = AudioApp(pid: ownerPID, key: owner.bundleIdentifier ?? name, name: name, bundleID: owner.bundleIdentifier, objects: [], isPlaying: false)
            }
            apps[ownerPID]?.objects.append(object)
            if running != 0 { apps[ownerPID]?.isPlaying = true }
        }
        return apps.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func processObjects() -> [AudioObjectID] {
        AudioSystem.objects(AudioSystem.system, kAudioHardwarePropertyProcessObjectList)
    }

    /// The app a process plays for: the one macOS holds responsible for it, else the first
    /// regular app among its parents. Nil for daemons and background agents.
    private static func regularApp(owning pid: pid_t) -> NSRunningApplication? {
        for start in [responsible(for: pid), pid] {
            var current = start
            for _ in 0..<6 where current > 1 {
                if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular {
                    return app
                }
                current = parent(of: current)
            }
        }
        return nil
    }

    /// Resolved at run time; without it, each process stands for itself.
    private static let responsibleFunction: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    private static func responsible(for pid: pid_t) -> pid_t {
        guard let responsibleFunction else { return pid }
        let owner = responsibleFunction(pid)
        return owner > 0 ? owner : pid
    }

    private static func parent(of pid: pid_t) -> pid_t {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return 0 }
        return pid_t(info.pbi_ppid)
    }
}
