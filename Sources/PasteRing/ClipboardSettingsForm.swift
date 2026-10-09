import AppKit
import SwiftUI

/// The Clipboard Manager's Settings tab: history, style and surface, each in a section.
struct ClipboardSettingsForm: View {
    @ObservedObject var settings: ClipboardSettings
    @ObservedObject var appearance: AppearanceSettings
    @ObservedObject var history: ClipboardHistory
    @FocusState private var historySizeFocused: Bool

    var body: some View {
        Form {
            Section("History") {
                LabeledContent("Keep up to") {
                    HStack {
                        TextField("Keep up to", value: settings.clamped(\.maxItems, to: ClipboardSettings.maxItemsRange), format: .number)
                            .focused($historySizeFocused)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Stepper("Keep up to", value: settings.clamped(\.maxItems, to: ClipboardSettings.maxItemsRange), in: ClipboardSettings.maxItemsRange, step: 5)
                            .labelsHidden()
                        Text("entries")
                    }
                }
            }

            Section("Style") {
                AppearancePreview(appearance: appearance, items: previewItems)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

                Picker("Style", selection: $settings.style) {
                    ForEach(OverlayStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }

                if settings.style == .simple {
                    slider("Width", value: $settings.simpleWidth, in: ClipboardSettings.simpleWidthRange, percent: false)
                    slider("Height", value: $settings.simpleHeight, in: ClipboardSettings.simpleHeightRange, percent: false)
                }

                if settings.style == .carousel {
                    slider("Width", value: $settings.carouselWidth, in: ClipboardSettings.carouselSizeRange, percent: false)
                    slider("Height", value: $settings.carouselHeight, in: ClipboardSettings.carouselSizeRange, percent: false)
                }

                if settings.style == .stack {
                    slider("Width", value: $settings.stackWidth, in: ClipboardSettings.stackWidthRange, percent: false)
                    slider("Height", value: $settings.stackHeight, in: ClipboardSettings.stackHeightRange, percent: false)
                }

                if settings.style == .grid {
                    LabeledContent("Grid shows") {
                        HStack {
                            Stepper("Grid shows", value: settings.clamped(\.gridSize, to: ClipboardSettings.gridSizeRange), in: ClipboardSettings.gridSizeRange, step: ClipboardSettings.gridColumns)
                                .labelsHidden()
                            Text("\(settings.gridSize) most recent entries")
                        }
                    }
                    slider("Width", value: $settings.gridCardWidth, in: ClipboardSettings.gridCardWidthRange, percent: false)
                    slider("Height", value: $settings.gridCardHeight, in: ClipboardSettings.gridCardHeightRange, percent: false)
                    Text("Shows fewer rows, and narrower tiles, when they would not fit the screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if settings.style == .ring {
                    LabeledContent("Ring shows") {
                        HStack {
                            Stepper("Ring shows", value: settings.clamped(\.ringSize, to: ClipboardSettings.ringSizeRange), in: ClipboardSettings.ringSizeRange)
                                .labelsHidden()
                            Text("\(settings.ringSize) most recent entries")
                        }
                    }
                    slider("Width", value: $settings.ringChipWidth, in: ClipboardSettings.ringChipWidthRange, percent: false)
                    slider("Height", value: $settings.ringChipHeight, in: ClipboardSettings.ringChipHeightRange, percent: false)
                }
            }

            Section("Surface") {
                ColorPicker("Tint", selection: $appearance.tint, supportsOpacity: false)
                slider("Tint strength", value: $appearance.tintOpacity, in: 0...0.6)
                slider("Selected highlight", value: $appearance.selectedTintOpacity, in: 0...0.6)
                slider("Shadow", value: $appearance.shadowRadius, in: 0...30, percent: false)
                slider("Dim screen", value: $appearance.backdropDim, in: 0...0.7)
            }

            Section {
                Button("Reset Style and Surface to Defaults") {
                    settings.resetAppearance()
                    appearance.reset()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // Forms focus their first text field on appear, which selects the whole number.
            DispatchQueue.main.async { historySizeFocused = false }
        }
    }

    /// Real entries when there are enough, so the preview shows familiar text and icons.
    private var previewItems: [ClipItem] {
        let samples = [
            ClipItem(text: "Meeting notes for Thursday", sourceBundleID: "com.apple.Notes"),
            ClipItem(text: "https://developer.apple.com/design", sourceBundleID: "com.apple.Safari"),
            ClipItem(text: "git push origin main", sourceBundleID: "com.apple.Terminal"),
            ClipItem(text: "Thanks, sounds good!", sourceBundleID: "com.apple.MobileSMS"),
        ]
        return Array((history.items + samples).prefix(4))
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, percent: Bool = true) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range)
                    .frame(width: 200)
                Text(percent ? "\(Int((value.wrappedValue * 100).rounded()))%" : "\(Int(value.wrappedValue.rounded()))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }
}

/// Overlay elements at real size over the desktop wallpaper, drawn with the current settings.
private struct AppearancePreview: View {
    @ObservedObject var appearance: AppearanceSettings
    let items: [ClipItem]
    @State private var wallpaper = Self.loadWallpaper()

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                ContentCard(item: items[0], isSelected: true, width: 200, height: 120, lineLimit: 3)
                ContentCard(item: items[1], isSelected: false, width: 200, height: 120, lineLimit: 3)
            }
            HStack(spacing: 14) {
                RingChip(item: items[2], isSelected: true)
                RingChip(item: items[3], isSelected: false)
            }
            PositionPill(text: "2 of 12")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .background {
            backdrop
            Color.black.opacity(appearance.backdropDim)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .environmentObject(appearance)
    }

    @ViewBuilder
    private var backdrop: some View {
        if let wallpaper {
            Image(nsImage: wallpaper)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(colors: [.indigo, .purple, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private static func loadWallpaper() -> NSImage? {
        guard let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        return NSImage(contentsOf: url)
    }
}
