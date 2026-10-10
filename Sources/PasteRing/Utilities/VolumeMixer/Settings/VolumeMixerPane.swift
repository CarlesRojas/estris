import AppKit
import CoreAudio
import SwiftUI

/// The Volume Mixer settings pane: the on/off switch, then a Mixer tab (the Mac's output and
/// microphone, and one row per app making sound) and an Excluded Apps tab.
struct VolumeMixerPane: View {
    private enum Tab: String, CaseIterable {
        case mixer = "Mixer"
        case excludedApps = "Excluded Apps"
    }

    private static let permissionURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    @ObservedObject var settings: VolumeMixerSettings
    @ObservedObject var state: VolumeMixerState
    let mixer: VolumeMixer
    @State private var tab = Tab.mixer

    var body: some View {
        UtilityPane(
            pane: .volumeMixer,
            summary: "Set the volume and device of your Mac's sound and microphone, and of each app.",
            isOn: $settings.isEnabled,
            tab: $tab
        ) { tab in
            switch tab {
            case .mixer:
                form
            case .excludedApps:
                // Left out of the mixer entirely: never listed, never changed.
                AppSwitchList(excluded: $settings.excludedApps)
            }
        }
    }

    private var form: some View {
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
                        .frame(width: 28, height: 28)
                }
                Text(verbatim: app.name)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if showsDevice {
                    DeviceMenu(options: outputOptions, selection: sound.outputUID) { mixer.setOutput($0, of: app) }
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

    /// The system output, each device, and the chosen one while it isn't connected.
    private var outputOptions: [DeviceOption<String?>] {
        var options = [DeviceOption<String?>(id: nil, name: String(localized: "Same as System"))]
        options += devices.map { DeviceOption(id: $0.uid, name: $0.name) }
        if let uid = sound.outputUID, !devices.contains(where: { $0.uid == uid }) {
            options.append(DeviceOption(id: uid, name: String(localized: "\(sound.outputName ?? uid) (not connected)")))
        }
        return options
    }
}

/// The Mac's output and microphone, one row each, laid out like an app's row. Used in Settings
/// and in the menu bar menu.
struct SystemSoundRows: View {
    @ObservedObject var state: VolumeMixerState
    let mixer: VolumeMixer
    var showsOutput = true
    var showsInput = true
    var showsDevice = true
    var showsPercentage = true

    var body: some View {
        if showsOutput {
            SystemSoundRow(
                title: "Output", icon: "hifispeaker.fill", tint: .blue,
                devices: state.outputDevices, selection: state.output, select: mixer.setOutputDevice,
                volume: state.outputVolume, isMuted: state.outputMuted,
                symbol: "speaker.wave.2.fill", mutedSymbol: "speaker.slash.fill",
                toggleMute: mixer.toggleOutputMute, setVolume: mixer.setOutputVolume,
                showsDevice: showsDevice, showsPercentage: showsPercentage
            )
        }
        if showsInput {
            SystemSoundRow(
                title: "Microphone", icon: "music.mic", tint: .orange,
                devices: state.inputDevices, selection: state.input, select: mixer.setInputDevice,
                volume: state.inputVolume, isMuted: state.inputMuted,
                symbol: "mic.fill", mutedSymbol: "mic.slash.fill",
                toggleMute: mixer.toggleInputMute, setVolume: mixer.setInputVolume,
                showsDevice: showsDevice, showsPercentage: showsPercentage
            )
        }
    }
}

/// An icon and title at the top left, the device at the top right, then mute, the volume
/// across the whole width and its percentage.
private struct SystemSoundRow: View {
    let title: LocalizedStringKey
    let icon: String
    let tint: Color
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
                // Where an app row has the app's icon: a coloured tile, so it doesn't read as
                // the mute button below it.
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.gradient)
                    .frame(width: 24, height: 24)
                    // App icons carry a clear margin; slightly smaller looks the same size.
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                Text(title)
                Spacer(minLength: 8)
                if showsDevice {
                    DeviceMenu(options: devices.map { DeviceOption(id: $0.id, name: $0.name) }, selection: selection, select: select)
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

struct DeviceOption<ID: Hashable>: Identifiable {
    let id: ID
    let name: String
}

/// Picks a device: its name and up-down arrows with no background until the pointer is over
/// it, hugging the right edge whatever the name's length (long names are cut short). The same
/// in Settings and the menu bar menu.
struct DeviceMenu<ID: Hashable>: View {
    let options: [DeviceOption<ID>]
    let selection: ID?
    let select: (ID) -> Void
    @State private var isHovered = false

    var body: some View {
        // Volume Mixer runs on macOS 14.4 or later only.
        if #available(macOS 14, *) {
            Menu {
                ForEach(options) { option in
                    Button {
                        select(option.id)
                    } label: {
                        if option.id == selection {
                            Label(option.name, systemImage: "checkmark")
                        } else {
                            Text(verbatim: option.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(verbatim: options.first { $0.id == selection }?.name ?? "")
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(isHovered ? 0.1 : 0))
                )
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .onHover { isHovered = $0 }
            // At most this wide, right-aligned in it.
            .frame(maxWidth: 200, alignment: .trailing)
        }
    }
}
