import AppKit
import SwiftUI

/// The Clipboard Manager's settings pane: the on/off switch, then Settings, History and
/// Excluded Apps tabs.
struct ClipboardManagerPane: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case settings = "Settings"
        case history = "History"
        case excludedApps = "Excluded Apps"

        var id: Self { self }
    }

    @ObservedObject var clipboard: ClipboardSettings
    @ObservedObject var appearance: AppearanceSettings
    @ObservedObject var history: ClipboardHistory
    @State private var tab = Tab.settings

    var body: some View {
        VStack(spacing: 0) {
            UtilityHeader(
                title: SettingsPane.clipboard.title,
                symbol: SettingsPane.clipboard.symbol,
                summary: "Keeps what you copy and lets you pick what to paste with a shortcut.",
                isOn: $clipboard.isEnabled
            )

            // The tabs stay pinned at the top; below them the selected tab fills the pane
            // and scrolls like any other settings page, with no box around it.
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.bottom, 4)

            content
                // Shrink to the space left; the tab's content scrolls.
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .settings:
            ClipboardSettingsForm(settings: clipboard, appearance: appearance, history: history)
        case .history:
            HistoryPreferences(history: history, settings: clipboard)
        case .excludedApps:
            ExcludedAppsList(settings: clipboard)
        }
    }
}
