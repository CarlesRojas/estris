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
        case .clipboard: "Clipboard Manager"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .clipboard: "doc.on.clipboard"
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
        NavigationSplitView {
            List(panes, selection: $selection) { pane in
                HStack {
                    Label(pane.title, systemImage: pane.symbol)
                    Spacer()
                    if let isOn = isOn(pane) {
                        StatusBadge(isOn: isOn)
                    }
                }
            }
            .searchable(text: $search, placement: .sidebar, prompt: "Search")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            switch selection ?? .general {
            case .general:
                GeneralPane(general: general)
            case .clipboard:
                clipboard.settingsPane()
            }
        }
        .environment(\.dateTimeFormat, general.dateTimeFormat)
        .frame(minWidth: 820, minHeight: 640)
        // Jump to the first match when the search hides the open pane.
        .onChange(of: search) { _ in
            if let selection, !panes.contains(selection), let first = panes.first {
                self.selection = first
            }
        }
    }
}
