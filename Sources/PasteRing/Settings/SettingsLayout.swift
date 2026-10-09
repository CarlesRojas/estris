import SwiftUI

/// Spacing shared by settings pages.
enum SettingsLayout {
    /// Extra room on both sides of a page, on top of the grouped form's own inset.
    static let pageMargin: CGFloat = 16
    /// Where grouped form boxes start, measured from the page edge, so headers line up.
    static let contentInset: CGFloat = pageMargin + 20
}

extension View {
    /// The horizontal margins every settings page uses.
    func settingsPage() -> some View {
        padding(.horizontal, SettingsLayout.pageMargin)
    }
}
