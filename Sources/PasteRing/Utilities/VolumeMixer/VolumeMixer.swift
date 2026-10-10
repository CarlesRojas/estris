import AppKit
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
    private var processListeners: [AudioObjectID: AudioListener] = [:]
    /// Apps heard playing since the mixer started; they stay listed while they're running.
    private var heard: Set<pid_t> = []
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
                    MainActor.assumeIsolated { self?.refreshApps() }
                })
            }
            refreshDevices()
        } else {
            systemListeners = []
            volumeListeners = []
            processListeners = [:]
            heard = []
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
        // Follow the volume of whichever devices are in use.
        volumeListeners = [(state.output, false), (state.input, true)].compactMap { pair -> AudioListener? in
            let (device, input) = pair
            guard let device else { return nil }
            return AudioListener(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: AudioSystem.scope(input: input)) { [weak self] in
                MainActor.assumeIsolated { self?.refreshVolumes() }
            }
        }
        refreshApps()
    }

    private func refreshVolumes() {
        state.outputVolume = state.output.flatMap { AudioSystem.volume(of: $0, input: false) }
        state.inputVolume = state.input.flatMap { AudioSystem.volume(of: $0, input: true) }
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
        let running = AudioApps.current()
        for app in running where app.isPlaying { heard.insert(app.pid) }
        state.apps = running.filter { heard.contains($0.pid) || !settings.sound(of: $0.key).isUntouched }
        heard.formIntersection(running.map(\.pid))

        // Starting or stopping playback changes this, not the list of processes.
        let objects = Set(running.flatMap(\.objects))
        processListeners = processListeners.filter { objects.contains($0.key) }
        for object in objects where processListeners[object] == nil {
            processListeners[object] = AudioListener(object, kAudioProcessPropertyIsRunningOutput) { [weak self] in
                MainActor.assumeIsolated { self?.refreshApps() }
            }
        }
        reconcileEngines(running)
    }

    func setVolume(_ volume: Double, of app: AudioApp) {
        var sound = settings.sound(of: app.key)
        // Snaps to the middle, where the app plays as it is.
        sound.volume = abs(volume - 1) < 0.03 ? 1 : volume
        settings.setSound(sound, of: app.key)
        reconcileEngines(state.apps)
    }

    func toggleMute(of app: AudioApp) {
        var sound = settings.sound(of: app.key)
        sound.isMuted.toggle()
        settings.setSound(sound, of: app.key)
        failed[app.pid] = nil
        reconcileEngines(state.apps)
    }

    /// Nil plays the app on the system output.
    func setOutput(_ uid: String?, of app: AudioApp) {
        var sound = settings.sound(of: app.key)
        sound.outputUID = uid
        sound.outputName = uid.flatMap { uid in state.outputDevices.first { $0.uid == uid }?.name }
        settings.setSound(sound, of: app.key)
        failed[app.pid] = nil
        reconcileEngines(state.apps)
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
                engines[app.pid] = try TapEngine(objects: app.objects, outputUID: outputUID, gain: gain)
                failed[app.pid] = nil
                state.failedApps.removeAll { $0 == app.name }
                log("\(app.name): playing at \(Int(gain * 100))% on \(outputUID)")
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
            log("\(state.apps.first { $0.pid == pid }?.name ?? "\(pid)"): back to its own sound")
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
