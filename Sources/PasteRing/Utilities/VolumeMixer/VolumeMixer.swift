import AppKit
import AudioToolbox
import Combine
import CoreAudio
import SwiftUI

/// What the Volume Mixer pane shows: the system's output and input, and each app making sound.
@MainActor
final class VolumeMixerState: ObservableObject {
    @Published var outputDevices: [AudioDevice] = []
    @Published var inputDevices: [AudioDevice] = []
    @Published var output: AudioObjectID?
    @Published var input: AudioObjectID?
    /// Nil when the device's volume can't be changed.
    @Published var outputVolume: Float?
    @Published var inputVolume: Float?
    /// Nil when the device can't be muted.
    @Published var outputMuted: Bool?
    @Published var inputMuted: Bool?
    @Published var apps: [AudioApp] = []
    /// Apps whose sound couldn't be changed, usually for a missing permission.
    @Published var failedApps: [String] = []
}

/// The Volume Mixer utility: the volume and device of the Mac's output and microphone, and a
/// volume, mute and output device for each app making sound, remembered per app. Owns
/// everything it needs, so the app only has to create it and call `start()`.
@MainActor
final class VolumeMixer {
    /// Per-app sound uses process taps, which work reliably from this version; on older
    /// versions the utility is hidden and never starts.
    static var isSupported: Bool {
        if #available(macOS 14.4, *) { return true }
        return false
    }

    let settings = VolumeMixerSettings()
    let state = VolumeMixerState()
    private let appLog: AppLog
    private var observers: Set<AnyCancellable> = []
    private var systemListeners: [AudioListener] = []
    private var volumeListeners: [AudioListener] = []
    private var processListeners: [AudioObjectID: [AudioListener]] = [:]
    /// A refresh asked for while one is waiting: one event fires several listeners at once.
    private var refreshQueued = false
    private var lastListSummary = ""
    /// Every app with an audio connection, playing or not; changed ones keep their sound even
    /// while they aren't listed.
    private var running: [AudioApp] = []
    /// One `TapEngine` per app whose sound is changed, by the app's process.
    private var engines: [pid_t: AnyObject] = [:]
    /// Audio objects of apps whose engine failed, so it isn't tried again on every change.
    private var failed: [pid_t: [AudioObjectID]] = [:]

    init(log: AppLog) {
        appLog = log
    }

    func start() {
        guard Self.isSupported else { return }
        // Published values arrive before the property changes; applying on the next turn of
        // the run loop reads the new ones.
        settings.$isEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &observers)
        // An app just excluded goes back to its own sound and leaves the list.
        settings.$excludedApps
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshApps() }
            .store(in: &observers)
    }

    /// The pane shown for this utility in Settings.
    func settingsPane() -> some View {
        VolumeMixerPane(settings: settings, state: state, mixer: self)
    }

    private func apply() {
        if settings.isEnabled {
            guard systemListeners.isEmpty else { return }
            let system = AudioSystem.system
            let refresh: () -> Void = { [weak self] in MainActor.assumeIsolated { self?.refreshDevices() } }
            systemListeners = [
                AudioListener(system, kAudioHardwarePropertyDevices, handler: refresh),
                AudioListener(system, kAudioHardwarePropertyDefaultOutputDevice, handler: refresh),
                AudioListener(system, kAudioHardwarePropertyDefaultInputDevice, handler: refresh),
            ]
            if #available(macOS 14.4, *) {
                systemListeners.append(AudioListener(system, kAudioHardwarePropertyProcessObjectList) { [weak self] in
                    MainActor.assumeIsolated { self?.queueRefreshApps() }
                })
            }
            refreshDevices()
        } else {
            systemListeners = []
            volumeListeners = []
            processListeners = [:]
            running = []
            failed = [:]
            stopAllEngines()
            state.apps = []
            state.failedApps = []
        }
    }

    // MARK: System output and input

    private func refreshDevices() {
        guard settings.isEnabled else { return }
        state.outputDevices = AudioSystem.devices(input: false)
        state.inputDevices = AudioSystem.devices(input: true)
        state.output = AudioSystem.defaultDevice(input: false)
        state.input = AudioSystem.defaultDevice(input: true)
        refreshVolumes()
        // Follow the volume and mute of whichever devices are in use.
        volumeListeners = [(state.output, false), (state.input, true)].flatMap { pair -> [AudioListener] in
            let (device, input) = pair
            guard let device else { return [] }
            return [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute].map { selector in
                AudioListener(device, selector, scope: AudioSystem.scope(input: input)) { [weak self] in
                    MainActor.assumeIsolated { self?.refreshVolumes() }
                }
            }
        }
        refreshApps()
    }

    private func refreshVolumes() {
        state.outputVolume = state.output.flatMap { AudioSystem.volume(of: $0, input: false) }
        state.inputVolume = state.input.flatMap { AudioSystem.volume(of: $0, input: true) }
        state.outputMuted = state.output.flatMap { AudioSystem.isMuted($0, input: false) }
        state.inputMuted = state.input.flatMap { AudioSystem.isMuted($0, input: true) }
    }

    func toggleOutputMute() {
        guard let device = state.output, let muted = state.outputMuted else { return }
        AudioSystem.setMuted(!muted, device, input: false)
        state.outputMuted = !muted
    }

    func toggleInputMute() {
        guard let device = state.input, let muted = state.inputMuted else { return }
        AudioSystem.setMuted(!muted, device, input: true)
        state.inputMuted = !muted
    }

    func setOutputVolume(_ volume: Float) {
        guard let device = state.output else { return }
        AudioSystem.setVolume(volume, of: device, input: false)
        state.outputVolume = volume
    }

    func setInputVolume(_ volume: Float) {
        guard let device = state.input else { return }
        AudioSystem.setVolume(volume, of: device, input: true)
        state.inputVolume = volume
    }

    func setOutputDevice(_ device: AudioObjectID) {
        AudioSystem.setDefaultDevice(device, input: false)
        log("output: \(state.outputDevices.first { $0.id == device }?.name ?? "\(device)")")
    }

    func setInputDevice(_ device: AudioObjectID) {
        AudioSystem.setDefaultDevice(device, input: true)
        log("input: \(state.inputDevices.first { $0.id == device }?.name ?? "\(device)")")
    }

    // MARK: Apps

    private func refreshApps() {
        guard settings.isEnabled, #available(macOS 14.4, *) else { return }
        let excluded = settings.excludedApps
        let running = AudioApps.current().filter { app in app.bundleID.map { !excluded.contains($0) } ?? true }
        self.running = running
        // Only what is making sound right now: a paused app leaves the list at once.
        state.apps = running.filter(\.isPlaying)
        logListIfChanged(running)

        // Starting or stopping playback changes these, not the list of processes. Every audio
        // process is followed, including helpers not yet matched to an app. Some macOS versions
        // change "running output" without telling; "running" and the devices it plays on
        // change with it, so all three are followed.
        let objects = Set(AudioApps.processObjects())
        processListeners = processListeners.filter { objects.contains($0.key) }
        let newObjects = objects.filter { processListeners[$0] == nil }
        for object in newObjects {
            let changed: () -> Void = { [weak self] in MainActor.assumeIsolated { self?.queueRefreshApps() } }
            processListeners[object] = [
                AudioListener(object, kAudioProcessPropertyIsRunningOutput, handler: changed),
                AudioListener(object, kAudioProcessPropertyIsRunning, handler: changed),
                AudioListener(object, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput, handler: changed),
            ]
        }
        if !newObjects.isEmpty {
            let listeners = processListeners.values.joined()
            log("following \(objects.count) audio processes: \(listeners.filter(\.isAdded).count) of \(listeners.count) listeners active")
        }
        reconcileEngines(running)
    }

    /// For the logs, whenever it changes: the audio processes, the apps found for them, which
    /// are playing, and which are listed.
    @available(macOS 14.4, *)
    private func logListIfChanged(_ running: [AudioApp]) {
        let apps = running.map { "\($0.name)" + ($0.isPlaying ? " (playing)" : "") }
        let unmatched = AudioApps.unmatched()
        let summary = "\(AudioApps.processObjects().count) audio processes; apps: \(apps.joined(separator: ", ")); "
            + "listed: \(state.apps.map(\.name).joined(separator: ", ")); "
            + "without an app: \(unmatched.isEmpty ? "none" : unmatched.joined(separator: ", "))"
        guard summary != lastListSummary else { return }
        lastListSummary = summary
        log(summary)
    }

    /// Refreshes once for a burst of notifications, right after it.
    private func queueRefreshApps() {
        guard !refreshQueued else { return }
        log("an audio process started, stopped or changed device")
        refreshQueued = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                self?.refreshQueued = false
                self?.refreshApps()
            }
        }
    }

    func setVolume(_ volume: Double, of app: AudioApp) {
        var sound = settings.sound(of: app.key)
        // Snaps to the middle, where the app plays as it is.
        sound.volume = abs(volume - 1) < 0.03 ? 1 : volume
        settings.setSound(sound, of: app.key)
        reconcileEngines(running)
    }

    func toggleMute(of app: AudioApp) {
        var sound = settings.sound(of: app.key)
        sound.isMuted.toggle()
        settings.setSound(sound, of: app.key)
        failed[app.pid] = nil
        reconcileEngines(running)
    }

    /// Nil plays the app on the system output.
    func setOutput(_ uid: String?, of app: AudioApp) {
        var sound = settings.sound(of: app.key)
        sound.outputUID = uid
        sound.outputName = uid.flatMap { uid in state.outputDevices.first { $0.uid == uid }?.name }
        settings.setSound(sound, of: app.key)
        failed[app.pid] = nil
        reconcileEngines(running)
    }

    /// Every app back to playing as it is.
    func reset() {
        settings.reset()
        failed = [:]
        state.failedApps = []
        refreshApps()
    }

    /// After granting the permission.
    func retry() {
        failed = [:]
        state.failedApps = []
        refreshApps()
    }

    /// Starts, updates or stops each app's engine to match its settings: an app only goes
    /// through PasteRing while its sound is changed.
    private func reconcileEngines(_ apps: [AudioApp]) {
        guard #available(macOS 14.4, *) else { return }
        let systemUID = state.output.flatMap(AudioSystem.uid(of:))
        var kept: Set<pid_t> = []
        for app in apps {
            let sound = settings.sound(of: app.key)
            // A chosen device that isn't connected falls back to the system output.
            let chosenUID = sound.outputUID.flatMap { uid in AudioSystem.device(uid: uid) != nil ? uid : nil }
            guard let outputUID = chosenUID ?? systemUID,
                  sound.volume != 1 || sound.isMuted || (chosenUID != nil && chosenUID != systemUID)
            else { continue }
            kept.insert(app.pid)
            let gain = Float(sound.isMuted ? 0 : sound.volume)
            if let engine = engines[app.pid] as? TapEngine, engine.objects == app.objects, engine.outputUID == outputUID {
                engine.gain = gain
                continue
            }
            (engines[app.pid] as? TapEngine)?.stop()
            engines[app.pid] = nil
            guard failed[app.pid] != app.objects else { continue }
            do {
                let engine = try TapEngine(objects: app.objects, outputUID: outputUID, gain: gain)
                engines[app.pid] = engine
                failed[app.pid] = nil
                state.failedApps.removeAll { $0 == app.name }
                let deviceName = state.outputDevices.first { $0.uid == outputUID }?.name ?? outputUID
                log("\(app.name): playing at \(Int(gain * 100))% on \(deviceName), \(app.objects.count) audio process(es)")
                // How it went, once the audio has had time to flow.
                let name = app.name
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak engine] in
                    MainActor.assumeIsolated {
                        guard let engine else { return }
                        self?.log("\(name) on \(deviceName) after 2 s: \(engine.diagnostics)")
                    }
                }
            } catch {
                failed[app.pid] = app.objects
                if !state.failedApps.contains(app.name) { state.failedApps.append(app.name) }
                log("\(app.name): can't change its sound (\(error)); System Audio Recording permission may be missing")
            }
        }
        // The rest play as macOS plays them.
        for (pid, engine) in engines where !kept.contains(pid) {
            (engine as? TapEngine)?.stop()
            engines[pid] = nil
            log("\(running.first { $0.pid == pid }?.name ?? "\(pid)"): back to its own sound")
        }
    }

    private func stopAllEngines() {
        guard #available(macOS 14.4, *) else { return }
        for engine in engines.values { (engine as? TapEngine)?.stop() }
        engines = [:]
    }

    private func log(_ message: String) {
        appLog.record(message, source: "Volume Mixer")
    }
}
