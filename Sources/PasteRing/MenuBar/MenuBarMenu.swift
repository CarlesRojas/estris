import SwiftUI

/// What clicking the menu bar icon shows, in the clipboard overlay's default frosted look: the
/// Volume Mixer while it is on (the parts chosen in Settings > Menu Bar), then Settings and
/// Quit side by side.
struct MenuBarMenu: View {
    static let width: CGFloat = 360

    @ObservedObject var settings: MenuBarSettings
    @ObservedObject var mixerSettings: VolumeMixerSettings
    @ObservedObject var mixerState: VolumeMixerState
    let mixer: VolumeMixer
    let openSettings: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if mixerSettings.isEnabled && VolumeMixer.isSupported {
                if settings.showsSystem {
                    header("System")
                    SystemSoundRows(state: mixerState, mixer: mixer, showsDevice: settings.showsDevices, showsPercentage: settings.showsPercentages)
                    Divider()
                }
                if settings.showsApps {
                    header("Apps")
                    if mixerState.apps.isEmpty {
                        Text("No app is playing sound.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(mixerState.apps) { app in
                        AppSoundRow(
                            app: app, sound: mixerSettings.sound(of: app.key), devices: mixerState.outputDevices, mixer: mixer,
                            showsDevice: settings.showsDevices, showsPercentage: settings.showsPercentages
                        )
                    }
                    Divider()
                }
            }
            HStack(spacing: 8) {
                menuButton("Settings", symbol: "gearshape", action: openSettings)
                menuButton("Quit", symbol: "power", action: quit)
            }
        }
        .padding(14)
        .frame(width: Self.width)
        .surface(cornerRadius: 18)
    }

    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// Half the menu's width each.
    private func menuButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}
