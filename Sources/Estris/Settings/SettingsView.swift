import AppKit
import Combine
import SwiftUI

/// One entry in the settings sidebar: the app-wide General pane, then one per utility.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case menuBar
    case clipboard
    case autoQuit
    case middleClick
    case remap
    case windowSnapping
    case focusFollowsMouse
    case dockPreview
    case keepAwake
    case roundedCorners
    case colorPicker
    case volumeMixer
    /// Hidden until unlocked from the version in General > About.
    case developer

    var id: Self { self }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .menuBar: String(localized: "Menu Bar")
        case .clipboard: String(localized: "Clipboard")
        case .autoQuit: String(localized: "Auto Quit")
        case .middleClick: String(localized: "Middle Click")
        case .remap: String(localized: "Remap")
        case .windowSnapping: String(localized: "Window Snapping")
        case .focusFollowsMouse: String(localized: "Focus Follows Mouse")
        case .dockPreview: String(localized: "Dock Preview")
        case .keepAwake: String(localized: "Keep Awake")
        case .roundedCorners: String(localized: "Rounded Corners")
        case .colorPicker: String(localized: "Color Picker")
        case .volumeMixer: String(localized: "Volume Mixer")
        case .developer: String(localized: "Developer")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .menuBar: "menubar.rectangle"
        case .clipboard: "list.clipboard"
        case .autoQuit: "xmark.app"
        case .middleClick: "hand.tap"
        case .remap: "keyboard"
        case .windowSnapping: "rectangle.split.2x1"
        case .focusFollowsMouse: "cursorarrow.rays"
        case .dockPreview: "dock.rectangle"
        case .keepAwake: "cup.and.saucer"
        case .roundedCorners: "display"
        case .colorPicker: "eyedropper"
        case .volumeMixer: "speaker.wave.2"
        case .developer: "hammer"
        }
    }

    /// What the sidebar search matches besides the title.
    var keywords: [String] {
        switch self {
        case .general:
            ["login", "startup", "language", "accessibility", "permission", "date", "time", "format", "version", "about"]
        case .menuBar:
            ["menu bar", "icon", "status", "symbol", "quit"]
        case .developer:
            ["logs", "debug", "developer", "diagnostics"]
        case .autoQuit:
            ["quit", "close", "window", "last window", "terminate", "excluded", "apps", "delay"]
        case .volumeMixer:
            ["volume", "sound", "audio", "mixer", "output", "speakers", "headphones", "microphone", "input", "mute", "apps"]
        case .colorPicker:
            ["color", "colour", "picker", "eyedropper", "hex", "rgb", "hsl", "swiftui", "sample"]
        case .keepAwake:
            ["awake", "sleep", "caffeinate", "display", "battery", "power", "timer"]
        case .roundedCorners:
            ["corners", "round", "radius", "screen", "display", "black"]
        case .dockPreview:
            ["dock", "preview", "thumbnail", "window", "hover", "close", "desktop", "screen recording"]
        case .focusFollowsMouse:
            ["focus", "mouse", "pointer", "hover", "window", "raise", "activate", "excluded", "apps", "delay"]
        case .windowSnapping:
            ["window", "snap", "tile", "half", "halves", "corner", "third", "maximize", "resize", "drag", "shortcut"]
        case .remap:
            ["keys", "keyboard", "mouse", "buttons", "mapping", "remap", "device", "event viewer", "mission control", "desktop", "volume", "brightness"]
        case .middleClick:
            ["trackpad", "mouse", "middle", "tap", "fingers", "click"]
        case .clipboard:
            ["history", "paste", "search", "image", "file", "rich text", "excluded", "apps", "expiry", "shortcut", "hotkey", "keyboard", "password", "duplicate", "date", "delete", "style", "default", "grid", "carousel", "stack", "ring", "tint", "shadow", "dim", "surface", "entries"]
        }
    }

    func matches(_ search: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return true }
        return title.lowercased().contains(query) || keywords.contains { $0.contains(query) }
    }
}

/// The sidebar's groups, in order: General, Menu Bar (and Developer) on their own under the search
/// field, then the utilities by what they work on.
enum SettingsGroup: CaseIterable, Identifiable {
    case app
    case tools
    case windows
    case input

    var id: Self { self }

    /// Shown small and faint above the group; none for the first.
    var title: String? {
        switch self {
        case .app: nil
        case .tools: String(localized: "Tools")
        case .windows: String(localized: "Windows & Apps")
        case .input: String(localized: "Keyboard & Mouse")
        }
    }

    var panes: [SettingsPane] {
        switch self {
        case .app: [.general, .menuBar, .developer]
        case .tools: [.clipboard, .colorPicker, .volumeMixer, .keepAwake, .roundedCorners]
        case .windows: [.windowSnapping, .focusFollowsMouse, .dockPreview, .autoQuit]
        case .input: [.remap, .middleClick]
        }
    }
}

/// What the Settings window is showing, shared by the sidebar and the detail column.
@MainActor
final class SettingsNavigation: ObservableObject {
    private let general: GeneralSettings
    private var observer: AnyCancellable?

    @Published var selection: SettingsPane? = .general
    @Published var search = "" {
        // Jump to the first match when the search hides the open pane.
        didSet {
            if let selection, !panes.contains(selection), let first = panes.first {
                self.selection = first
            }
        }
    }

    init(general: GeneralSettings) {
        self.general = general
        // The sidebar rebuilds when the Developer pane is unlocked or hidden; it opens when
        // unlocked.
        observer = general.$showsDeveloperSettings.dropFirst().sink { [weak self] shows in
            self?.objectWillChange.send()
            if shows {
                self?.selection = .developer
            } else if self?.selection == .developer {
                self?.selection = .general
            }
        }
    }

    /// Every pane shown, in sidebar order.
    var panes: [SettingsPane] {
        SettingsGroup.allCases.flatMap(panes(in:))
    }

    func panes(in group: SettingsGroup) -> [SettingsPane] {
        group.panes.filter { pane in
            (pane != .developer || general.showsDeveloperSettings)
                && (pane != .volumeMixer || VolumeMixer.isSupported)
                && (pane != .dockPreview || DockPreview.isSupported)
                && pane.matches(search)
        }
    }
}

/// The Settings sidebar: a search field and one row per pane, grouped, each utility showing
/// whether it is on. To add a utility, add a `SettingsPane` case, put it in a `SettingsGroup`,
/// report its state in `isOn(_:)` and show its pane in `SettingsDetail`.
struct SettingsSidebar: View {
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var clipboardSettings: ClipboardSettings
    @ObservedObject var autoQuitSettings: AutoQuitSettings
    @ObservedObject var middleClickSettings: MiddleClickSettings
    @ObservedObject var remapSettings: RemapSettings
    @ObservedObject var windowSnappingSettings: WindowSnappingSettings
    @ObservedObject var focusFollowsMouseSettings: FocusFollowsMouseSettings
    @ObservedObject var dockPreviewSettings: DockPreviewSettings
    @ObservedObject var keepAwakeSettings: KeepAwakeSettings
    @ObservedObject var roundedCornersSettings: RoundedCornersSettings
    @ObservedObject var colorPickerSettings: ColorPickerSettings
    @ObservedObject var volumeMixerSettings: VolumeMixerSettings

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $navigation.search)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

            List(selection: $navigation.selection) {
                ForEach(SettingsGroup.allCases) { group in
                    let panes = navigation.panes(in: group)
                    if let title = group.title {
                        // A search that hides every pane of a group hides its title too.
                        if !panes.isEmpty {
                            Section {
                                rows(panes)
                            } header: {
                                Text(title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        rows(panes)
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func rows(_ panes: [SettingsPane]) -> some View {
        ForEach(panes) { pane in
            SidebarRow(pane: pane, isOn: isOn(pane), isSelected: navigation.selection == pane)
                // Typing a letter would otherwise jump to the pane starting with it.
                .background(TypeSelectDisabler())
        }
    }

    /// Whether a utility is switched on; nil for panes that are not a utility.
    private func isOn(_ pane: SettingsPane) -> Bool? {
        switch pane {
        case .general, .menuBar: nil
        case .clipboard: clipboardSettings.isEnabled
        case .autoQuit: autoQuitSettings.isEnabled
        case .middleClick: middleClickSettings.isEnabled
        case .remap: remapSettings.isEnabled
        case .windowSnapping: windowSnappingSettings.isEnabled
        case .focusFollowsMouse: focusFollowsMouseSettings.isEnabled
        case .dockPreview: dockPreviewSettings.isEnabled
        case .keepAwake: keepAwakeSettings.isEnabled
        case .roundedCorners: roundedCornersSettings.isEnabled
        case .colorPicker: colorPickerSettings.isEnabled
        case .volumeMixer: volumeMixerSettings.isEnabled
        case .developer: nil
        }
    }
}

/// The selected pane. Pinned to the space it is given, so a long pane scrolls instead of
/// trying to grow the window.
struct SettingsDetail: View {
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var general: GeneralSettings
    let clipboard: ClipboardManager
    let autoQuit: AutoQuit
    let middleClick: MiddleClick
    let remap: Remap
    let windowSnapping: WindowSnapping
    let focusFollowsMouse: FocusFollowsMouse
    let dockPreview: DockPreview
    let keepAwake: KeepAwake
    let roundedCorners: RoundedCorners
    let colorPicker: ScreenColorPicker
    let volumeMixer: VolumeMixer
    let menuBarSettings: MenuBarSettings
    let log: AppLog

    var body: some View {
        GeometryReader { proxy in
            Group {
                switch navigation.selection ?? .general {
                case .general:
                    GeneralPane(general: general)
                case .menuBar:
                    MenuBarPane(settings: menuBarSettings)
                case .clipboard:
                    clipboard.settingsPane()
                case .autoQuit:
                    autoQuit.settingsPane()
                case .middleClick:
                    middleClick.settingsPane()
                case .remap:
                    remap.settingsPane()
                case .windowSnapping:
                    windowSnapping.settingsPane()
                case .focusFollowsMouse:
                    focusFollowsMouse.settingsPane()
                case .dockPreview:
                    dockPreview.settingsPane()
                case .keepAwake:
                    keepAwake.settingsPane()
                case .roundedCorners:
                    roundedCorners.settingsPane()
                case .colorPicker:
                    colorPicker.settingsPane()
                case .volumeMixer:
                    volumeMixer.settingsPane()
                case .developer:
                    DeveloperPane(general: general, log: log)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .environment(\.dateTimeFormat, general.dateTimeFormat)
    }
}

/// A sidebar row: icon, title and, for utilities, the On/Off badge.
private struct SidebarRow: View {
    let pane: SettingsPane
    let isOn: Bool?
    let isSelected: Bool

    var body: some View {
        if #available(macOS 14, *) {
            HighlightAwareSidebarRow(pane: pane, isOn: isOn)
        } else {
            SidebarRowContent(pane: pane, isOn: isOn, isHighlighted: isSelected)
        }
    }
}

/// Reads the row's highlight straight from the list: it changes in the same frame the
/// selection colour is drawn, unlike the selection value, which arrives a moment later.
@available(macOS 14, *)
private struct HighlightAwareSidebarRow: View {
    let pane: SettingsPane
    let isOn: Bool?
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        SidebarRowContent(pane: pane, isOn: isOn, isHighlighted: prominence == .increased)
    }
}

private struct SidebarRowContent: View {
    let pane: SettingsPane
    let isOn: Bool?
    /// On the selected row's coloured highlight: icon and badge turn white.
    let isHighlighted: Bool

    var body: some View {
        HStack {
            Label {
                Text(pane.title)
            } icon: {
                Image(systemName: pane.symbol)
                    .font(.system(size: 15))
                    // The label colour (white in dark mode), white on the highlight. Not the accent
                    // colour: it wouldn't stand out from the selected row's highlight.
                    .foregroundStyle(isHighlighted ? Color.white : Color.primary)
                    // Centred in a fixed box: symbols sit on the text baseline by default,
                    // which pushes taller ones like the clipboard down.
                    .frame(width: 22, height: 22, alignment: .center)
            }
            Spacer()
            if let isOn {
                StatusBadge(isOn: isOn, onSelectedRow: isHighlighted)
            }
        }
        .transaction { $0.animation = nil }
    }
}

/// Turns off "type to select" on the list it is placed in: SwiftUI has no setting for it, so
/// it finds the AppKit table behind the list.
private struct TypeSelectDisabler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // The view joins the table on the next pass.
        DispatchQueue.main.async {
            var ancestor = view.superview
            while let current = ancestor, !(current is NSTableView) {
                ancestor = current.superview
            }
            (ancestor as? NSTableView)?.allowsTypeSelect = false
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
