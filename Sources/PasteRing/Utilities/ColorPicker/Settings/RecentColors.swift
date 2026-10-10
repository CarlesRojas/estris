import AppKit
import SwiftUI

/// The colors picked lately as round swatches, most recent first; a click copies one in the
/// chosen format. Used in Settings and the menu bar menu.
struct RecentColors: View {
    @ObservedObject var settings: ColorPickerSettings
    /// How many swatches fit in one row.
    var columns = 16
    /// At most this many rows.
    var rows = 1
    let copy: (String) -> Void

    var body: some View {
        if settings.recentColors.isEmpty {
            Text("No colors picked yet.")
                .foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), alignment: .leading, spacing: 6) {
                ForEach(settings.recentColors.prefix(columns * rows), id: \.self) { hex in
                    Swatch(hex: hex, settings: settings) { copy(hex) }
                }
            }
        }
    }
}

private struct Swatch: View {
    let hex: String
    @ObservedObject var settings: ColorPickerSettings
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: NSColor(hex: hex) ?? .clear))
                .overlay(Circle().strokeBorder(Color.primary.opacity(isHovered ? 0.6 : 0.2), lineWidth: isHovered ? 2 : 1))
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        // The value it copies, in the chosen format.
        .help(Text(verbatim: NSColor(hex: hex).map { settings.format.string(for: $0, hashPrefix: settings.hashPrefix) } ?? hex))
    }
}
