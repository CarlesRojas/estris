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
            ["history", "paste", "search", "image", "file", "rich text", "excluded", "apps", "expiry", "quick", "pick", "shortcut", "hotkey", "keyboard", "password", "duplicate", "date", "delete", "style", "default", "grid", "carousel", "stack", "ring", "tint", "shadow", "dim", "surface", "entries"]
        }
    }

    func matches(_ search: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return true }
        return title.lowercased().contains(query) || keywords.contains { $0.contains(query) }
    }
}

/// The Settings window: a sidebar with General and one pane per utility.
/// To add a utility, add a `SettingsPane` case, show its pane here and report its on/off
/// state in `isOn(_:)`.
struct SettingsView: View {
    @ObservedObject var general: GeneralSettings
    let clipboard: ClipboardManager
    @ObservedObject private var clipboardSettings: ClipboardSettings
    @State private var selection: SettingsPane? = .general
    @State private var search = ""

    init(general: GeneralSettings, clipboard: ClipboardManager) {
        self.general = general
        self.clipboard = clipboard
        clipboardSettings = clipboard.settings
    }

    /// Whether a utility is switched on; nil for panes that are not a utility.
    private func isOn(_ pane: SettingsPane) -> Bool? {
        switch pane {
        case .general: nil
        case .clipboard: clipboardSettings.isEnabled
        }
    }

    private var panes: [SettingsPane] {
        SettingsPane.allCases.filter { $0.matches(search) }
    }

    var body: some View {
        // Pin the whole view to the window's size, whatever the panes would like to be, so it
        // can never be laid out taller than the window and shift off screen. Long panes
        // scroll inside instead.
        GeometryReader { proxy in
            splitView
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        // Cover the title bar too: the sidebar reaches the top like in System Settings, and
        // the split view keeps its contents clear of the window buttons on its own.
        .ignoresSafeArea()
    }

    private var splitView: some View {
        NavigationSplitView {
            List(panes, selection: $selection) { pane in
                HStack {
                    // Outlined symbols in the accent colour, as in Finder's and Mail's sidebars;
                    // white on the selected row's highlight.
                    Label {
                        Text(pane.title)
                    } icon: {
                        Image(systemName: pane.symbol)
                            .foregroundStyle(selection == pane ? Color.white : Color.accentColor)
                            // Switches with the selection highlight, without fading.
                            .transaction { $0.animation = nil }
                    }
                    Spacer()
                    if let isOn = isOn(pane) {
                        StatusBadge(isOn: isOn)
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $search, placement: .sidebar, prompt: "Search")
            .modifier(HidesSidebarToggle())
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            Group {
                switch selection ?? .general {
                case .general:
                    GeneralPane(general: general)
                case .clipboard:
                    clipboard.settingsPane()
                }
            }
            // The split view sizes the window from the detail column's preferred size. A long
            // form prefers its full height (taller than the screen), which pushed everything
            // off the top and bottom when switching panes. Fixed small minimum and ideal sizes
            // keep the window as it is; the forms scroll instead.
            .frame(
                minWidth: 520, idealWidth: 640, maxWidth: .infinity,
                minHeight: 0, idealHeight: 500, maxHeight: .infinity,
                alignment: .top
            )
        }
        .environment(\.dateTimeFormat, general.dateTimeFormat)
        // Jump to the first match when the search hides the open pane.
        .onChange(of: search) { _ in
            if let selection, !panes.contains(selection), let first = panes.first {
                self.selection = first
            }
        }
    }
}


/// System Settings has no button to hide its sidebar.
private struct HidesSidebarToggle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 14, *) {
            content.toolbar(removing: .sidebarToggle)
        } else {
            content
        }
    }
}
