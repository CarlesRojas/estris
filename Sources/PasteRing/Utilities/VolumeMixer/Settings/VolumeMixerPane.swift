import AppKit
import CoreAudio
import SwiftUI

/// The Volume Mixer settings pane: the on/off switch, the Mac's output and microphone, and one
/// row per app making sound.
struct VolumeMixerPane: View {
    private static let permissionURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    @ObservedObject var settings: VolumeMixerSettings
    @ObservedObject var state: VolumeMixerState
    let mixer: VolumeMixer

    var body: some View {
        VStack(spacing: 0) {
            UtilityHeader(
                title: SettingsPane.volumeMixer.title,
                symbol: SettingsPane.volumeMixer.symbol,
                summary: "Set the volume and device of your Mac's sound and microphone, and of each app.",
                isOn: $settings.isEnabled
            )

            Form {
                if settings.isEnabled {
                    Section("Output") {
                        devicePicker(state.outputDevices, selection: state.output, set: mixer.setOutputDevice)
                        volumeSlider(state.outputVolume, low: "speaker.fill", high: "speaker.wave.3.fill", set: mixer.setOutputVolume)
                    }
                    Section("Microphone") {
                        devicePicker(state.inputDevices, selection: state.input, set: mixer.setInputDevice)
                        volumeSlider(state.inputVolume, low: "mic", high: "mic.fill", set: mixer.setInputVolume)
                    }
                    Section("Apps") {
                        if !state.failedApps.isEmpty {
                            permissionNotice
                        }
                        if state.apps.isEmpty {
                            Text("No app is playing sound.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(state.apps) { app in
                            AppSoundRow(app: app, sound: settings.sound(of: app.key), devices: state.outputDevices, mixer: mixer)
                        }
                    }
                }
                Section {
                    Button("Reset to Defaults") { mixer.reset() }
                }
            }
            .formStyle(.grouped)
            .settingsPage()
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func devicePicker(_ devices: [AudioDevice], selection: AudioObjectID?, set: @escaping (AudioObjectID) -> Void) -> some View {
        Picker("Device", selection: Binding(get: { selection ?? AudioObjectID(kAudioObjectUnknown) }, set: set)) {
            ForEach(devices) { device in
                Text(verbatim: device.name).tag(device.id)
            }
        }
    }

    private func volumeSlider(_ volume: Float?, low: String, high: String, set: @escaping (Float) -> Void) -> some View {
        LabeledContent("Volume") {
            HStack(spacing: 8) {
                Image(systemName: low).foregroundStyle(.secondary)
                Slider(value: Binding(get: { Double(volume ?? 0) }, set: { set(Float($0)) }), in: 0...1)
                Image(systemName: high).foregroundStyle(.secondary)
            }
        }
        .disabled(volume == nil)
    }

    private var permissionNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PasteRing couldn't change the sound of \(state.failedApps.formatted(.list(type: .and))). Allow it under System Audio Recording Only in System Settings > Privacy & Security > Screen & System Audio Recording.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open System Settings") { NSWorkspace.shared.open(Self.permissionURL) }
                Button("Try Again") { mixer.retry() }
            }
        }
    }
}

/// One app: its name and output device, then mute and volume. The middle of the slider plays
/// it as it is.
private struct AppSoundRow: View {
    let app: AudioApp
    let sound: AppSound
    let devices: [AudioDevice]
    let mixer: VolumeMixer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let icon = AppIcons.icon(for: app.bundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                Text(verbatim: app.name)
                if app.isPlaying {
                    Image(systemName: "waveform")
                        .foregroundStyle(.secondary)
                        .help("Playing")
                }
                Spacer()
                Picker("Output", selection: Binding(get: { sound.outputUID }, set: { mixer.setOutput($0, of: app) })) {
                    Text("Same as System").tag(String?.none)
                    ForEach(devices) { device in
                        Text(verbatim: device.name).tag(Optional(device.uid))
                    }
                    if let uid = sound.outputUID, !devices.contains(where: { $0.uid == uid }) {
                        Text("\(sound.outputName ?? uid) (not connected)").tag(Optional(uid))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            HStack(spacing: 8) {
                Button {
                    mixer.toggleMute(of: app)
                } label: {
                    Image(systemName: sound.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 20)
                }
                .buttonStyle(.borderless)
                .help(sound.isMuted ? Text("Unmute") : Text("Mute"))
                Slider(value: Binding(get: { sound.volume }, set: { mixer.setVolume($0, of: app) }), in: 0...2)
                    .disabled(sound.isMuted)
                Text(verbatim: "\(Int((sound.volume * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
    }
}
