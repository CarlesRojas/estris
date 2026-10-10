import SwiftUI

/// Spacing shared by settings pages.
enum SettingsLayout {
    /// Extra room on both sides of a page's content, on top of the grouped form's own inset.
    static let pageMargin: CGFloat = 16
    /// Where grouped form boxes start, measured from the page edge, so headers line up.
    static let contentInset: CGFloat = pageMargin + 20
}

extension View {
    /// The horizontal margins every settings page uses. They go inside the scroll view, so
    /// the scroll bar stays near the window's right edge with room between it and the content.
    func settingsPage() -> some View {
        modifier(SettingsPageMargins())
    }

    /// A search field (or other control) pinned above a scrolling settings list, spanning
    /// the same width as the boxes below it.
    func pinnedAboveList() -> some View {
        padding(.horizontal, SettingsLayout.contentInset)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }
}

/// A form row's switch at the mini size, as System Settings uses: about the height of the
/// buttons and pop-ups in other rows, so rows keep one height. The utility's own on/off switch
/// in the header stays large.
struct RowSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration)
            .toggleStyle(.switch)
            .controlSize(.mini)
    }
}

private struct SettingsPageMargins: ViewModifier {
    func body(content: Content) -> some View {
        margins(content.toggleStyle(RowSwitchStyle()))
    }

    @ViewBuilder
    private func margins(_ content: some View) -> some View {
        if #available(macOS 14, *) {
            content
                .contentMargins(.horizontal, SettingsLayout.pageMargin, for: .scrollContent)
                // Almost flush with the window edge.
                .contentMargins(.trailing, 2, for: .scrollIndicators)
        } else {
            content.padding(.horizontal, SettingsLayout.pageMargin)
        }
    }
}
