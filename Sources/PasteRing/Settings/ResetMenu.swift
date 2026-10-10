import SwiftUI

extension View {
    /// A right-click menu with Reset to Default, which puts back just this setting. Greyed
    /// out while it already has its default.
    func resetMenu(isDefault: Bool, reset: @escaping () -> Void) -> some View {
        contextMenu {
            Button("Reset to Default", action: reset)
                .disabled(isDefault)
        }
    }

    /// The same, for a setting bound directly.
    func resetMenu<Value: Equatable>(_ value: Binding<Value>, to defaultValue: Value) -> some View {
        resetMenu(isDefault: value.wrappedValue == defaultValue) { value.wrappedValue = defaultValue }
    }
}
