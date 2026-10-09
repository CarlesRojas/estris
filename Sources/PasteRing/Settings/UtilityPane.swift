import SwiftUI

/// The layout every utility's settings page shares: its header with the on/off switch, then
/// a tab switcher pinned at the top and the selected tab filling the rest.
struct UtilityPane<Tab, Content: View>: View
where Tab: CaseIterable & Hashable & RawRepresentable, Tab.RawValue == String, Tab.AllCases: RandomAccessCollection {
    let pane: SettingsPane
    let summary: String
    @Binding var isOn: Bool
    @Binding var tab: Tab
    @ViewBuilder let content: (Tab) -> Content

    var body: some View {
        VStack(spacing: 0) {
            UtilityHeader(title: pane.title, symbol: pane.symbol, summary: summary, isOn: $isOn)

            Picker("View", selection: $tab) {
                ForEach(Array(Tab.allCases), id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // The large size is the current macOS look for a page's main switcher (rounder,
            // roomier segments); a fixed width keeps it calm.
            .controlSize(.large)
            .frame(width: CGFloat(Tab.allCases.count) * 140)
            .padding(.bottom, 4)

            content(tab)
                // Shrink to the space left; the tab's content scrolls.
                .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
