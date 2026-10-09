import AppKit
import SwiftUI

/// The Clipboard Manager's settings pane: the on/off switch, then Settings and History tabs.
struct ClipboardManagerPane: View {
    private enum Tab: Hashable {
        case settings
        case history
    }

    @ObservedObject var clipboard: ClipboardSettings
    @ObservedObject var appearance: AppearanceSettings
    @ObservedObject var history: ClipboardHistory
    @State private var tab = Tab.settings

    var body: some View {
        VStack(spacing: 0) {
            UtilityHeader(
                title: "Clipboard Manager",
                symbol: "doc.on.clipboard",
                summary: "Keeps what you copy and lets you pick what to paste with a shortcut.",
                isOn: $clipboard.isEnabled
            )

            Divider()

            Picker("View", selection: $tab) {
                Text("Settings").tag(Tab.settings)
                Text("History").tag(Tab.history)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.vertical, 12)

            switch tab {
            case .settings:
                ClipboardSettingsForm(settings: clipboard, appearance: appearance, history: history)
            case .history:
                HistoryPreferences(history: history)
            }
        }
    }
}
