import AppKit
import SwiftUI

/// The Clipboard Manager's settings pane: the on/off switch, then Settings, History and
/// Excluded Apps tabs.
struct ClipboardManagerPane: View {
    private enum Tab: Hashable {
        case settings
        case history
        case excludedApps
    }

    @ObservedObject var clipboard: ClipboardSettings
    @ObservedObject var appearance: AppearanceSettings
    @ObservedObject var history: ClipboardHistory
    @State private var tab = Tab.settings

    var body: some View {
        VStack(spacing: 0) {
            UtilityHeader(
                title: "Clipboard Manager",
                symbol: SettingsPane.clipboard.symbol,
                color: SettingsPane.clipboard.color,
                summary: "Keeps what you copy and lets you pick what to paste with a shortcut.",
                isOn: $clipboard.isEnabled
            )

            // The standard macOS tab view.
            TabView(selection: $tab) {
                ClipboardSettingsForm(settings: clipboard, appearance: appearance, history: history)
                    .tabItem { Text("Settings") }
                    .tag(Tab.settings)
                HistoryPreferences(history: history, settings: clipboard)
                    .tabItem { Text("History") }
                    .tag(Tab.history)
                ExcludedAppsList(settings: clipboard)
                    .tabItem { Text("Excluded Apps") }
                    .tag(Tab.excludedApps)
            }
            .padding([.horizontal, .bottom], 16)
            // Shrink to the space left; the tabs' content scrolls.
            .frame(minHeight: 0, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
