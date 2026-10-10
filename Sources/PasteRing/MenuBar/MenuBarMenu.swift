import SwiftUI

/// What clicking the menu bar icon shows, in the clipboard overlay's default frosted look: the
/// Volume Mixer, the Clipboard and the Color Picker while each is on (the parts chosen in
/// Settings > Menu Bar), then Settings and Quit side by side.
struct MenuBarMenu: View {
    static let width: CGFloat = 360

    @ObservedObject var settings: MenuBarSettings
    @ObservedObject var mixerSettings: VolumeMixerSettings
    @ObservedObject var mixerState: VolumeMixerState
    let mixer: VolumeMixer
    @ObservedObject var clipboardSettings: ClipboardSettings
    @ObservedObject var history: ClipboardHistory
    @ObservedObject var colorPickerSettings: ColorPickerSettings
    let paste: (ClipItem) -> Void
    let clearHistory: () -> Void
    let pickColor: () -> Void
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
            if clipboardSettings.isEnabled && (settings.showsClipboardHistory || settings.showsClearHistory) {
                header("Clipboard")
                if settings.showsClipboardHistory {
                    if history.items.isEmpty {
                        Text("Nothing copied yet.")
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 0) {
                        ForEach(history.items.prefix(settings.clipboardEntries)) { item in
                            HistoryEntryButton(item: item) { paste(item) }
                        }
                    }
                }
                if settings.showsClearHistory {
                    menuButton("Clear History", symbol: "trash", action: clearHistory)
                        .disabled(history.items.isEmpty)
                }
                Divider()
            }
            if colorPickerSettings.isEnabled && settings.showsColorPicker {
                menuButton("Pick a Color", symbol: "eyedropper", action: pickColor)
                Divider()
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

/// A clipboard entry in the menu: where it was copied from and one line of it. A click pastes
/// it into the app in front.
private struct HistoryEntryButton: View {
    let item: ClipItem
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                SourceIcon(item: item, size: 20)
                ClipContentView(item: item, singleLine: true)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: 20, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.1 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
