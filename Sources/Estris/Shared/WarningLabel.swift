import SwiftUI

/// A short warning under a row: an orange triangle, then the text in the secondary color.
/// Orange text itself is too faint to read on a light background; the triangle carries the
/// warning by its shape as well as its color.
struct WarningLabel: View {
    let text: Text

    /// Text already localized; a literal goes to the localized initializer below, as with `Text`.
    init<S: StringProtocol>(_ text: S) {
        self.text = Text(text)
    }

    init(_ key: LocalizedStringKey) {
        text = Text(key)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            text
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
