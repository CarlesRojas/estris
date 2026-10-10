import AppKit
import SwiftUI

/// The Clipboard Manager's Settings tab: General, Appearance and Shortcuts sections.
struct ClipboardSettingsForm: View {
    @ObservedObject var settings: ClipboardSettings
    @ObservedObject var appearance: AppearanceSettings
    @ObservedObject var history: ClipboardHistory
    @FocusState private var historySizeFocused: Bool

    var body: some View {
        Form {
            PermissionsSection(uses: ClipboardManagerPane.permissions)
            Section("General") {
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
                .resetMenu($settings.maxItems, to: ClipboardSettings.Default.maxItems)
                Picker("Delete entries", selection: $settings.expiry) {
                    ForEach(HistoryExpiry.allCases) { expiry in
                        Text(expiry.title).tag(expiry)
                    }
                }
                .resetMenu($settings.expiry, to: ClipboardSettings.Default.expiry)
                Toggle(isOn: $settings.ignorePasswords) {
                    Text("Ignore passwords")
                    Text("Skips text copied from password fields and password managers.")
                }
                .resetMenu($settings.ignorePasswords, to: ClipboardSettings.Default.ignorePasswords)
                Toggle(isOn: $settings.recordImages) {
                    Text("Record images")
                    Text("Keeps copied images in the history alongside text and files.")
                }
                .resetMenu($settings.recordImages, to: ClipboardSettings.Default.recordImages)
                Toggle(isOn: $settings.pasteAsPlainText) {
                    Text("Paste as plain text")
                    Text("Drops fonts, colours and other formatting, so pasted text matches where it goes.")
                }
                .resetMenu($settings.pasteAsPlainText, to: ClipboardSettings.Default.pasteAsPlainText)
                Toggle(isOn: $settings.removeDuplicates) {
                    Text("Remove duplicates")
                    Text("Copying something already in the history moves it to the top instead of adding it again.")
                }
                .resetMenu($settings.removeDuplicates, to: ClipboardSettings.Default.removeDuplicates)
                Toggle(isOn: $settings.moveToTopOnPaste) {
                    Text("Move pasted entry to the top")
                    Text("When off, the history keeps the order things were copied in, and ⌘V keeps pasting the last copied text.")
                }
                .resetMenu($settings.moveToTopOnPaste, to: ClipboardSettings.Default.moveToTopOnPaste)
            }

            Section("Appearance") {
                AppearancePreview(appearance: appearance, items: previewItems)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

                Picker("Style", selection: $settings.style) {
                    ForEach(OverlayStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .resetMenu($settings.style, to: ClipboardSettings.Default.style)

                if settings.style == .simple {
                    slider("Width", value: $settings.simpleWidth, in: ClipboardSettings.simpleWidthRange, percent: false, default: ClipboardSettings.Default.simpleWidth)
                    slider("Height", value: $settings.simpleHeight, in: ClipboardSettings.simpleHeightRange, percent: false, default: ClipboardSettings.Default.simpleHeight)
                }

                if settings.style == .carousel {
                    slider("Width", value: $settings.carouselWidth, in: ClipboardSettings.carouselSizeRange, percent: false, default: ClipboardSettings.Default.carouselWidth)
                    slider("Height", value: $settings.carouselHeight, in: ClipboardSettings.carouselSizeRange, percent: false, default: ClipboardSettings.Default.carouselHeight)
                }

                if settings.style == .stack {
                    slider("Width", value: $settings.stackWidth, in: ClipboardSettings.stackWidthRange, percent: false, default: ClipboardSettings.Default.stackWidth)
                    slider("Height", value: $settings.stackHeight, in: ClipboardSettings.stackHeightRange, percent: false, default: ClipboardSettings.Default.stackHeight)
                }

                if settings.style == .grid {
                    LabeledContent("Grid shows") {
                        HStack {
                            Stepper("Grid shows", value: settings.clamped(\.gridSize, to: ClipboardSettings.gridSizeRange), in: ClipboardSettings.gridSizeRange, step: ClipboardSettings.gridColumns)
                                .labelsHidden()
                            Text("\(settings.gridSize) most recent entries")
                        }
                    }
                    .resetMenu($settings.gridSize, to: ClipboardSettings.Default.gridSize)
                    slider("Width", value: $settings.gridCardWidth, in: ClipboardSettings.gridCardWidthRange, percent: false, default: ClipboardSettings.Default.gridCardWidth)
                    slider("Height", value: $settings.gridCardHeight, in: ClipboardSettings.gridCardHeightRange, percent: false, default: ClipboardSettings.Default.gridCardHeight)
                }

                if settings.style == .ring {
                    LabeledContent("Ring shows") {
                        HStack {
                            Stepper("Ring shows", value: settings.clamped(\.ringSize, to: ClipboardSettings.ringSizeRange), in: ClipboardSettings.ringSizeRange)
                                .labelsHidden()
                            Text("\(settings.ringSize) most recent entries")
                        }
                    }
                    .resetMenu($settings.ringSize, to: ClipboardSettings.Default.ringSize)
                    slider("Width", value: $settings.ringChipWidth, in: ClipboardSettings.ringChipWidthRange, percent: false, default: ClipboardSettings.Default.ringChipWidth)
                    slider("Height", value: $settings.ringChipHeight, in: ClipboardSettings.ringChipHeightRange, percent: false, default: ClipboardSettings.Default.ringChipHeight)
                }

                Toggle("Show when entries were copied", isOn: $settings.showCopyDate)
                    .resetMenu($settings.showCopyDate, to: ClipboardSettings.Default.showCopyDate)
                Toggle("Show delete button", isOn: $settings.showDeleteButton)
                    .resetMenu($settings.showDeleteButton, to: ClipboardSettings.Default.showDeleteButton)

                ColorPicker("Tint", selection: $appearance.tint, supportsOpacity: false)
                    .resetMenu($appearance.tint, to: AppearanceSettings.defaultTint)
                slider("Tint strength", value: $appearance.tintOpacity, in: 0...0.6, default: AppearanceSettings.defaultTintOpacity)
                slider("Selected highlight", value: $appearance.selectedTintOpacity, in: 0...0.6, default: AppearanceSettings.defaultSelectedTintOpacity)
                slider("Shadow", value: $appearance.shadowRadius, in: 0...30, percent: false, default: AppearanceSettings.defaultShadowRadius)
                slider("Dim screen", value: $appearance.backdropDim, in: 0...0.7, default: AppearanceSettings.defaultBackdropDim)
                Button("Reset Appearance to Defaults") {
                    settings.resetAppearance()
                    appearance.reset()
                }
            }

            Section {
                ForEach(settings.shortcuts) { shortcut in
                    LabeledContent(shortcut == settings.shortcuts.first ? String(localized: "Open overlay") : String(localized: "Alternative")) {
                        HStack {
                            ShortcutRecorder(shortcut: settings.shortcutBinding(shortcut))
                            if settings.shortcuts.count > 1 {
                                Button {
                                    settings.shortcuts.removeAll { $0.id == shortcut.id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .help("Remove this shortcut")
                                .accessibilityLabel(Text("Remove this shortcut"))
                            }
                        }
                    }
                    // Only the first has a default; alternatives are added by hand.
                    .resetMenu(isDefault: shortcut != settings.shortcuts.first || shortcut == ClipboardSettings.defaultShortcut) {
                        settings.resetMainShortcut()
                    }
                }
                Button("Add Alternative Shortcut") {
                    settings.addAlternativeShortcut()
                }
            } header: {
                Text("Shortcuts")
            }
            Section {
                Button("Reset to Defaults") { settings.reset(); appearance.reset() }
            }
        }
        .formStyle(.grouped)
        .settingsPage()
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

    private func slider(_ title: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>, percent: Bool = true, default defaultValue: Double) -> some View {
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
        .resetMenu(value, to: defaultValue)
    }
}
