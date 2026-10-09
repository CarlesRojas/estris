import AppKit
import SwiftUI

/// The first row of every utility's settings pane: what it is, and a switch that turns the
/// whole utility on or off.
struct UtilityHeader: View {
    let title: String
    let symbol: String
    var color: Color = .blue
    let summary: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(symbol: symbol, color: isOn ? color : .gray, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

/// The on/off state shown at the right of a sidebar row.
struct StatusBadge: View {
    /// The system green in light mode. In dark mode the system green is too bright for white
    /// text, so a deeper green keeps it readable (about 5:1).
    private static let onColor = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.10, green: 0.48, blue: 0.20, alpha: 1)
            : .systemGreen
    })

    let isOn: Bool

    var body: some View {
        Text(isOn ? "On" : "Off")
            .font(.caption.weight(.semibold))
            .foregroundStyle(isOn ? Color.white : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(isOn ? Self.onColor : Color.secondary.opacity(0.2))
            )
            .accessibilityLabel(isOn ? "On" : "Off")
    }
}
