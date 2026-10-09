import AppKit
import Combine
import SwiftUI

/// One entry in the settings sidebar: the app-wide General pane, then one per utility.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case clipboard
    case autoQuit
    case middleClick
    /// Hidden until unlocked from the version in General > About.
    case developer

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .clipboard: "Clipboard"
        case .autoQuit: "Auto Quit"
        case .middleClick: "Middle Click"
        case .developer: "Developer"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .clipboard: "list.clipboard"
        case .autoQuit: "xmark.app"
        case .middleClick: "hand.tap"
        case .developer: "hammer"
        }
    }

    /// What the sidebar search matches besides the title.
    var keywords: [String] {
        switch self {
        case .general:
            ["login", "startup", "language", "accessibility", "permission", "date", "time", "format", "version", "about"]
        case .developer:
            ["logs", "debug", "developer", "diagnostics"]
        case .autoQuit:
            ["quit", "close", "window", "last window", "terminate", "excluded", "apps", "delay"]
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

    var panes: [SettingsPane] {
        SettingsPane.allCases.filter { pane in
            (pane != .developer || general.showsDeveloperSettings) && pane.matches(search)
        }
    }
}

/// The Settings sidebar: a search field and one row per pane, each utility showing whether
/// it is on. To add a utility, add a `SettingsPane` case, report its state in `isOn(_:)`
/// and show its pane in `SettingsDetail`.
struct SettingsSidebar: View {
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var clipboardSettings: ClipboardSettings
    @ObservedObject var autoQuitSettings: AutoQuitSettings
    @ObservedObject var middleClickSettings: MiddleClickSettings

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $navigation.search)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

            List(navigation.panes, selection: $navigation.selection) { pane in
                SidebarRow(pane: pane, isOn: isOn(pane), isSelected: navigation.selection == pane)
            }
            .listStyle(.sidebar)
        }
    }

    /// Whether a utility is switched on; nil for panes that are not a utility.
    private func isOn(_ pane: SettingsPane) -> Bool? {
        switch pane {
        case .general: nil
        case .clipboard: clipboardSettings.isEnabled
        case .autoQuit: autoQuitSettings.isEnabled
        case .middleClick: middleClickSettings.isEnabled
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
    let log: AppLog

    var body: some View {
        GeometryReader { proxy in
            Group {
                switch navigation.selection ?? .general {
                case .general:
                    GeneralPane(general: general)
                case .clipboard:
                    clipboard.settingsPane()
                case .autoQuit:
                    autoQuit.settingsPane()
                case .middleClick:
                    middleClick.settingsPane()
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
                    // The label colour (white in dark mode), white on the highlight.
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
