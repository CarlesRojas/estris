import AppKit
import SwiftUI

/// One entry in the settings sidebar: the app-wide General pane, then one per utility.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case clipboard

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .clipboard: "Clipboard"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .clipboard: "list.clipboard"
        }
    }

    /// What the sidebar search matches besides the title.
    var keywords: [String] {
        switch self {
        case .general:
            ["login", "startup", "language", "accessibility", "permission", "date", "time", "format", "version", "about"]
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
    @Published var selection: SettingsPane? = .general
    @Published var search = "" {
        // Jump to the first match when the search hides the open pane.
        didSet {
            if let selection, !panes.contains(selection), let first = panes.first {
                self.selection = first
            }
        }
    }

    var panes: [SettingsPane] {
        SettingsPane.allCases.filter { $0.matches(search) }
    }
}

/// The Settings sidebar: a search field and one row per pane, each utility showing whether
/// it is on. To add a utility, add a `SettingsPane` case, report its state in `isOn(_:)`
/// and show its pane in `SettingsDetail`.
struct SettingsSidebar: View {
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var clipboardSettings: ClipboardSettings

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $navigation.search)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

            List(navigation.panes, selection: $navigation.selection) { pane in
                HStack {
                    // The label colour (white in dark mode), and white on the selected row's
                    // highlight.
                    Label {
                        Text(pane.title)
                    } icon: {
                        Image(systemName: pane.symbol)
                            .foregroundStyle(navigation.selection == pane ? Color.white : Color.primary)
                            // Switches with the selection highlight, without fading.
                            .transaction { $0.animation = nil }
                    }
                    Spacer()
                    if let isOn = isOn(pane) {
                        StatusBadge(isOn: isOn, onSelectedRow: navigation.selection == pane)
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    /// Whether a utility is switched on; nil for panes that are not a utility.
    private func isOn(_ pane: SettingsPane) -> Bool? {
        switch pane {
        case .general: nil
        case .clipboard: clipboardSettings.isEnabled
        }
    }
}

/// The selected pane. Pinned to the space it is given, so a long pane scrolls instead of
/// trying to grow the window.
struct SettingsDetail: View {
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var general: GeneralSettings
    let clipboard: ClipboardManager

    var body: some View {
        GeometryReader { proxy in
            Group {
                switch navigation.selection ?? .general {
                case .general:
                    GeneralPane(general: general)
                case .clipboard:
                    clipboard.settingsPane()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .environment(\.dateTimeFormat, general.dateTimeFormat)
    }
}
