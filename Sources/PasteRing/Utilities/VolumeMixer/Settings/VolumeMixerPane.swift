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
                    Section("System") {
                        SystemSoundRows(state: state, mixer: mixer)
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
struct AppSoundRow: View {
    let app: AudioApp
    let sound: AppSound
    let devices: [AudioDevice]
    let mixer: VolumeMixer
    var showsDevice = true
    var showsPercentage = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let icon = AppIcons.icon(for: app.bundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                Text(verbatim: app.name)
                Spacer()
                if showsDevice {
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
                    .devicePickerWidth()
                }
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
                // In a form, a slider keeps an empty label column at its left unless hidden.
                Slider(value: Binding(get: { sound.volume }, set: { mixer.setVolume($0, of: app) }), in: 0...2)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .disabled(sound.isMuted)
                if showsPercentage {
                    Text(verbatim: "\(Int((sound.volume * 100).rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// The Mac's output and microphone, one row each, laid out like an app's row. Used in Settings
/// and in the menu bar menu.
struct SystemSoundRows: View {
    @ObservedObject var state: VolumeMixerState
    let mixer: VolumeMixer
    var showsDevice = true
    var showsPercentage = true

    var body: some View {
        SystemSoundRow(
            title: "Output", icon: "hifispeaker",
            devices: state.outputDevices, selection: state.output, select: mixer.setOutputDevice,
            volume: state.outputVolume, isMuted: state.outputMuted,
            symbol: "speaker.wave.2.fill", mutedSymbol: "speaker.slash.fill",
            toggleMute: mixer.toggleOutputMute, setVolume: mixer.setOutputVolume,
            showsDevice: showsDevice, showsPercentage: showsPercentage
        )
        SystemSoundRow(
            title: "Microphone", icon: "mic",
            devices: state.inputDevices, selection: state.input, select: mixer.setInputDevice,
            volume: state.inputVolume, isMuted: state.inputMuted,
            symbol: "mic.fill", mutedSymbol: "mic.slash.fill",
            toggleMute: mixer.toggleInputMute, setVolume: mixer.setInputVolume,
            showsDevice: showsDevice, showsPercentage: showsPercentage
        )
    }
}

/// An icon and title at the top left, the device at the top right, then mute, the volume
/// across the whole width and its percentage.
private struct SystemSoundRow: View {
    let title: LocalizedStringKey
    let icon: String
    let devices: [AudioDevice]
    let selection: AudioObjectID?
    let select: (AudioObjectID) -> Void
    let volume: Float?
    let isMuted: Bool?
    let symbol: String
    let mutedSymbol: String
    let toggleMute: () -> Void
    let setVolume: (Float) -> Void
    let showsDevice: Bool
    let showsPercentage: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Where an app row has the app's icon and name.
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 20, height: 20)
                Text(title)
                Spacer()
                if showsDevice {
                    Picker("Device", selection: Binding(get: { selection ?? AudioObjectID(kAudioObjectUnknown) }, set: select)) {
                        ForEach(devices) { device in
                            Text(verbatim: device.name).tag(device.id)
                        }
                    }
                    .labelsHidden()
                    .devicePickerWidth()
                }
            }
            HStack(spacing: 8) {
                Button(action: toggleMute) {
                    Image(systemName: isMuted == true ? mutedSymbol : symbol)
                        .frame(width: 20)
                }
                .buttonStyle(.borderless)
                .disabled(isMuted == nil)
                .help(isMuted == true ? Text("Unmute") : Text("Mute"))
                // In a form, a slider keeps an empty label column at its left unless hidden.
                Slider(value: Binding(get: { Double(volume ?? 0) }, set: { setVolume(Float($0)) }), in: 0...1)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .disabled(volume == nil || isMuted == true)
                if showsPercentage {
                    Text(verbatim: volume.map { "\(Int(($0 * 100).rounded()))%" } ?? "")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

extension View {
    /// Every device picker the same width, whatever the device names; long ones are cut short.
    func devicePickerWidth() -> some View {
        frame(width: 170)
    }
}
