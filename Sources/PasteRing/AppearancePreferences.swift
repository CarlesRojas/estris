import AppKit
import SwiftUI

struct AppearancePreferences: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var appearance: AppearanceSettings
    @ObservedObject var history: ClipboardHistory

    var body: some View {
        VStack(spacing: 0) {
            AppearancePreview(appearance: appearance, items: previewItems)
                .padding([.horizontal, .top], 20)

            Form {
                Section("Overlay") {
                    Picker("Style", selection: $settings.style) {
                        ForEach(OverlayStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }

                    if settings.style == .simple {
                        slider("Width", value: $settings.simpleWidth, in: AppSettings.simpleWidthRange, percent: false)
                        slider("Height", value: $settings.simpleHeight, in: AppSettings.simpleHeightRange, percent: false)
                    }

                    if settings.style == .grid {
                        LabeledContent("Grid shows") {
                            HStack {
                                Stepper("Grid shows", value: settings.clamped(\.gridSize, to: AppSettings.gridSizeRange), in: AppSettings.gridSizeRange, step: AppSettings.gridColumns)
                                    .labelsHidden()
                                Text("\(settings.gridSize) most recent entries")
                            }
                        }
                        slider("Card width", value: $settings.gridCardWidth, in: AppSettings.gridCardWidthRange, percent: false)
                    }

                    if settings.style == .ring {
                        LabeledContent("Ring shows") {
                            HStack {
                                Stepper("Ring shows", value: settings.clamped(\.ringSize, to: AppSettings.ringSizeRange), in: AppSettings.ringSizeRange)
                                    .labelsHidden()
                                Text("\(settings.ringSize) most recent entries")
                            }
                        }
                    }
                }

                Section("Surface") {
                    Picker("Renderer", selection: $appearance.renderer) {
                        ForEach(SurfaceRenderer.allCases) { renderer in
                            Text(renderer.title).tag(renderer)
                        }
                    }
                    if appearance.renderer.needsMacOS26 && !supportsLiquidGlass {
                        Text("Needs macOS 26. Drawing with Material instead.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if appearance.renderer == .vibrancy {
                        Picker("Material", selection: $appearance.vibrancyMaterial) {
                            ForEach(VibrancyMaterial.allCases) { material in
                                Text(material.title).tag(material)
                            }
                        }
                    }
                    if appearance.renderer == .swiftUIGlass {
                        Toggle("Interactive", isOn: $appearance.interactive)
                    }
                    ColorPicker("Tint", selection: $appearance.tint, supportsOpacity: false)
                    slider("Tint strength", value: $appearance.tintOpacity, in: 0...0.6)
                    slider("Selected highlight", value: $appearance.selectedTintOpacity, in: 0...0.6)
                    slider("Shadow", value: $appearance.shadowRadius, in: 0...30, percent: false)
                    slider("Dim screen", value: $appearance.backdropDim, in: 0...0.7)
                }

                Section {
                    Button("Reset to Defaults") {
                        settings.resetAppearance()
                        appearance.reset()
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 600, height: 720)
    }

    private var supportsLiquidGlass: Bool {
        if #available(macOS 26, *) { return true }
        return false
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
        .environment(\.surfaceInPreview, true)
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
