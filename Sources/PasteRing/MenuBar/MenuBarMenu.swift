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
    let copyColor: (String) -> Void
    let openSettings: () -> Void
    let quit: () -> Void

    /// Whether any group shows above Settings and Quit.
    private var showsAnyGroup: Bool {
        let mixer = mixerSettings.isEnabled && VolumeMixer.isSupported
            && ((settings.showsSystem && (settings.showsOutput || settings.showsInput)) || settings.showsApps)
        let clipboard = clipboardSettings.isEnabled && (settings.showsClipboardHistory || settings.showsClearHistory)
        let colorPicker = colorPickerSettings.isEnabled && (settings.showsColorPicker || settings.showsRecentColors)
        return mixer || clipboard || colorPicker
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if mixerSettings.isEnabled && VolumeMixer.isSupported {
                if settings.showsSystem && (settings.showsOutput || settings.showsInput) {
                    group("System Volume") {
                        SystemSoundRows(
                            state: mixerState, mixer: mixer,
                            showsOutput: settings.showsOutput, showsInput: settings.showsInput,
                            showsDevice: settings.showsDevices, showsPercentage: settings.showsPercentages
                        )
                    }
                }
                if settings.showsApps {
                    group("Apps Volume") {
                        if !mixerState.canChangeApps {
                            Text("Allow System Audio Recording to change each app's sound.")
                                .foregroundStyle(.orange)
                        }
                        if mixerState.apps.isEmpty {
                            Text("No app is playing sound.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(mixerState.apps) { app in
                            AppSoundRow(
                                app: app, sound: mixerSettings.sound(of: app.key), devices: mixerState.outputDevices, mixer: mixer,
                                showsDevice: settings.showsDevices, showsPercentage: settings.showsPercentages,
                                canChange: mixerState.canChangeApps
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
            if colorPickerSettings.isEnabled && (settings.showsColorPicker || settings.showsRecentColors) {
                group("Color Picker") {
                    if settings.showsRecentColors {
                        RecentColors(settings: colorPickerSettings, columns: 8, copy: copyColor)
                    }
                    if settings.showsColorPicker {
                        menuButton("Pick a Color", symbol: "eyedropper", action: pickColor)
                    }
                }
            }
            HStack(spacing: 8) {
                menuButton("Settings", symbol: "gearshape", action: openSettings)
                menuButton("Quit", symbol: "power", action: quit)
            }
            // Set apart from the groups above: three times their gap.
            .padding(.top, showsAnyGroup ? 16 : 0)
        }
        .padding(Self.padding)
        .frame(width: Self.width)
        // Apart from the overlay's surface, so each group's box stands out.
        .background(Self.menuShade, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .surface(cornerRadius: Self.cornerRadius)
    }

    /// Around the groups and the buttons.
    private static let padding: CGFloat = 10
    /// The Settings and Quit buttons' height: they are capsules.
    private static let buttonHeight: CGFloat = 28
    /// Concentric with the capsule buttons at the bottom, and the groups with the menu.
    private static let cornerRadius: CGFloat = buttonHeight / 2 + padding
    private static let groupRadius: CGFloat = cornerRadius - padding
    /// Dark mode: the menu darker and its groups a lighter grey. Light mode the other way
    /// round: the menu almost white and its groups a light grey.
    private static let menuShade = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.black.withAlphaComponent(0.18)
            : NSColor.white.withAlphaComponent(0.8)
    })
    private static let groupFill = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.black.withAlphaComponent(0.05)
    })

    /// One utility's part of the menu, in its own lighter box, concentric with the menu.
    private func group<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(title)
            content()
        }
        .padding(Self.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.groupFill, in: RoundedRectangle(cornerRadius: Self.groupRadius, style: .continuous))
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
                .frame(maxWidth: .infinity, minHeight: Self.buttonHeight)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(Color.primary.opacity(0.1), in: Capsule())
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
