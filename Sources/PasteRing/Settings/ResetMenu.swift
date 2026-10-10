import SwiftUI

/// About the padding a grouped form puts around a row's content.
private let rowInset: CGFloat = 8

extension View {
    /// A right-click menu with Reset to Default, which puts back just this setting. Greyed
    /// out while it already has its default. As a form row (`fillsRow`), the whole row
    /// answers, its background and the form's padding included, not only its text and
    /// controls.
    @ViewBuilder
    func resetMenu(isDefault: Bool, fillsRow: Bool = true, reset: @escaping () -> Void) -> some View {
        if fillsRow {
            frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle().inset(by: -rowInset))
                .modifier(ResetMenu(isDefault: isDefault, reset: reset))
        } else {
            modifier(ResetMenu(isDefault: isDefault, reset: reset))
        }
    }

    /// The same, for a setting bound directly.
    func resetMenu<Value: Equatable>(_ value: Binding<Value>, to defaultValue: Value, fillsRow: Bool = true) -> some View {
        resetMenu(isDefault: value.wrappedValue == defaultValue, fillsRow: fillsRow) { value.wrappedValue = defaultValue }
    }
}

private struct ResetMenu: ViewModifier {
    let isDefault: Bool
    let reset: () -> Void

    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Reset to Default", action: reset)
                .disabled(isDefault)
        }
    }
}
