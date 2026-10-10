import AppKit
import SwiftUI

/// The Clipboard Manager's settings pane: the on/off switch, then Settings, History and
/// Excluded Apps tabs.
struct ClipboardManagerPane: View {
    /// What it needs, for its Permissions section and the prompt when it's turned on.
    static let permissions: [PermissionUse] = [
        PermissionUse(permission: .accessibility, reason: "Only to paste the entry you pick into the app you're working in.", without: "Without it, the history still records, and picking an entry copies it to paste yourself with ⌘V."),
    ]

    private enum Tab: String, CaseIterable {
        case settings = "Settings"
        case history = "History"
        case excludedApps = "Excluded Apps"
    }

    @ObservedObject var clipboard: ClipboardSettings
    @ObservedObject var appearance: AppearanceSettings
    @ObservedObject var history: ClipboardHistory
    @State private var tab = Tab.settings

    var body: some View {
        UtilityPane(
            pane: .clipboard,
            summary: "Keeps what you copy and lets you pick what to paste with a shortcut.",
            isOn: $clipboard.isEnabled,
            permissions: Self.permissions,
            tab: $tab
        ) { _ in
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .settings:
            ClipboardSettingsForm(settings: clipboard, appearance: appearance, history: history)
        case .history:
            HistoryPreferences(history: history, settings: clipboard)
        case .excludedApps:
            AppSwitchList(excluded: $clipboard.excludedApps)
        }
    }
}
