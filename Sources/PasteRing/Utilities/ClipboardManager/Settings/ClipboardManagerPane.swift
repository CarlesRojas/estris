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
                title: "Clipboard Manager",
                symbol: SettingsPane.clipboard.symbol,
                color: SettingsPane.clipboard.color,
                summary: "Keeps what you copy and lets you pick what to paste with a shortcut.",
                isOn: $clipboard.isEnabled
            )

            // Laid out like the standard tab view (tabs straddling the top edge of a box), but
            // with the box's corners and bottom edge matched to the sidebar.
            ZStack(alignment: .top) {
                content
                    .padding(.top, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: PaneStyle.cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PaneStyle.cornerRadius, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor))
                    )
                    .padding(.top, 12)

                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, PaneStyle.bottomInset)
            // Shrink to the space left; the tabs' content scrolls.
            .frame(minHeight: 0, maxHeight: .infinity)
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
