import SwiftUI

/// The first row of every utility's settings pane: what it is, and a switch that turns the
/// whole utility on or off.
struct UtilityHeader: View {
    let title: String
    let symbol: String
    let summary: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(isOn ? Color.accentColor : .secondary)
                .frame(width: 40, height: 40)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
    /// Dark enough for white text to stay readable (about 5:1), in light and dark mode.
    private static let onColor = Color(.sRGB, red: 0.10, green: 0.48, blue: 0.20)

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
