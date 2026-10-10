import SwiftUI

/// The Menu Bar pane: which icon PasteRing shows in the menu bar, all in view to click.
struct MenuBarPane: View {
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 16)

    @ObservedObject var general: GeneralSettings

    var body: some View {
        VStack(spacing: 0) {
            UtilityHeader(
                title: SettingsPane.menuBar.title,
                symbol: SettingsPane.menuBar.symbol,
                summary: "Choose the icon PasteRing shows in the menu bar."
            )

            Form {
                Section("Icon") {
                    LazyVGrid(columns: Self.columns, spacing: 4) {
                        ForEach(MenuBarIcon.all, id: \.self) { icon in
                            iconButton(icon)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button("Reset to Defaults") { general.menuBarIcon = MenuBarIcon.app }
                }
            }
            .formStyle(.grouped)
            .settingsPage()
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func iconButton(_ icon: String) -> some View {
        let isSelected = general.menuBarIcon == icon
        return Button {
            general.menuBarIcon = icon
        } label: {
            Image(systemName: MenuBarIcon.symbol(for: icon))
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
