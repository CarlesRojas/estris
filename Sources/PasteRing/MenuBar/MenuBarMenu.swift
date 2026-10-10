import AppKit
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
        VStack(alignment: .leading, spacing: 8) {
            if mixerSettings.isEnabled && VolumeMixer.isSupported {
                if settings.showsSystem {
                    group("System") {
                        SystemSoundRows(state: mixerState, mixer: mixer, showsDevice: settings.showsDevices, showsPercentage: settings.showsPercentages)
                    }
                }
                if settings.showsApps {
                    group("Apps") {
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
                    }
                }
            }
            if clipboardSettings.isEnabled && (settings.showsClipboardHistory || settings.showsClearHistory) {
                group("Clipboard") {
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
                }
            }
            if colorPickerSettings.isEnabled && settings.showsColorPicker {
                group("Color Picker") {
                    menuButton("Pick a Color", symbol: "eyedropper", action: pickColor)
                }
            }
            HStack(spacing: 8) {
                menuButton("Settings", symbol: "gearshape", action: openSettings)
                menuButton("Quit", symbol: "power", action: quit)
            }
        }
        .padding(10)
        .frame(width: Self.width)
        // Darker than the overlay's surface, so each group's lighter box stands out.
        .background(Self.menuShade, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .surface(cornerRadius: Self.cornerRadius)
    }

    private static let cornerRadius: CGFloat = 18
    private static let menuShade = Color.black.opacity(0.18)
    /// White on light menus, a grey above the menu on dark ones.
    private static let groupFill = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.white.withAlphaComponent(0.55)
    })

    /// One utility's part of the menu, in its own lighter box, concentric with the menu.
    private func group<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(title)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.groupFill, in: RoundedRectangle(cornerRadius: Self.cornerRadius - 10, style: .continuous))
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
