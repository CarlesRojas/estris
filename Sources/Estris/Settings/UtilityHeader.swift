import AppKit
import SwiftUI

/// The first row of every utility's settings pane: what it is, and a switch that turns the
/// whole utility on or off (none for panes that aren't a utility, such as Developer).
struct UtilityHeader: View {
    let title: String
    let symbol: String
    let summary: LocalizedStringKey
    var isOn: Binding<Bool>?
    /// Asked for when the switch is turned on, if any isn't allowed yet.
    var permissions: [PermissionUse] = []
    /// What the switch is at first, for its Reset to Default.
    var defaultIsOn = false
    @State private var asksForPermissions = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(isOn?.wrappedValue ?? true ? Color.accentColor : .secondary)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if let isOn {
                Toggle(title, isOn: isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.large)
                    .resetMenu(isOn, to: defaultIsOn, fillsRow: false)
                    .onChange(of: isOn.wrappedValue) { on in
                        if on, !missing.isEmpty { asksForPermissions = true }
                    }
                    .alert(Text("Allow what \(title) needs?"), isPresented: $asksForPermissions) {
                        Button("Allow") { missing.forEach { $0.permission.request() } }
                        Button("Not Now", role: .cancel) {}
                    } message: {
                        permissionsMessage
                    }
            }
        }
        // Lines up with the grouped boxes below.
        .padding(.horizontal, SettingsLayout.contentInset)
        .padding(.vertical, 14)
    }
}

extension UtilityHeader {
    private var missing: [PermissionUse] {
        permissions.filter { $0.permission.isGranted != true }
    }

    /// Each missing permission and what it is for, one paragraph each.
    private var permissionsMessage: Text {
        missing.enumerated().reduce(Text(verbatim: "")) { text, item in
            let (index, use) = item
            return text + (index > 0 ? Text(verbatim: "\n\n") : Text(verbatim: ""))
                + Text(use.permission.title).bold() + Text(verbatim: ": ") + Text(use.reason)
        }
    }
}

/// The on/off state shown at the right of a sidebar row.
struct StatusBadge: View {
    /// White in dark mode and black in light mode, with the text the opposite.
    private static let onFill = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
    })
    private static let onText = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .white
    })

    let isOn: Bool
    /// On the selected row's coloured highlight it is always white with black text when on,
    /// and a faint white outline when off.
    var onSelectedRow = false

    var body: some View {
        // The same in every language.
        Text(verbatim: isOn ? "On" : "Off")
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(fill))
            .overlay {
                if onSelectedRow && !isOn {
                    Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
                }
            }
            .accessibilityLabel(isOn ? String(localized: "On") : String(localized: "Off"))
    }

    private var foreground: Color {
        switch (onSelectedRow, isOn) {
        case (true, true): .black
        case (true, false): .white.opacity(0.85)
        case (false, true): Self.onText
        case (false, false): .secondary
        }
    }

    private var fill: Color {
        switch (onSelectedRow, isOn) {
        case (true, true): .white
        case (true, false): .clear
        case (false, true): Self.onFill
        case (false, false): Color.secondary.opacity(0.2)
        }
    }
}
