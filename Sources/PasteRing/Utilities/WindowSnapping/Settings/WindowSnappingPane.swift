import Carbon.HIToolbox
import SwiftUI

/// The Window Snapping settings pane: the on/off switch, then dragging, gestures and the
/// shortcuts on one page.
struct WindowSnappingPane: View {
    @ObservedObject var settings: WindowSnappingSettings

    /// The modifiers that can be chosen, in the usual order, with their names.
    private static let modifierKeys: [(flag: Int, symbol: String, name: LocalizedStringKey)] = [
        (controlKey, "⌃", "Control"),
        (optionKey, "⌥", "Option"),
        (shiftKey, "⇧", "Shift"),
        (cmdKey, "⌘", "Command"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            UtilityHeader(
                title: SettingsPane.windowSnapping.title,
                symbol: SettingsPane.windowSnapping.symbol,
                summary: "Snap windows to halves, corners and thirds with shortcuts or by dragging them to a screen edge.",
                isOn: $settings.isEnabled
            )

            Form {
                dragging
                gestures
                shortcuts
            }
            .formStyle(.grouped)
            .settingsPage()
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var dragging: some View {
        Section("Dragging") {
            Toggle("Snap by dragging a window to a screen edge", isOn: $settings.snapsByDragging)
            LabeledContent("Edge area") {
                HStack {
                    Slider(value: $settings.edgeArea, in: WindowSnappingSettings.edgeAreaRange, step: 1)
                        .frame(width: 200)
                    Text("\(Int(settings.edgeArea)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }
            }
            .disabled(!settings.snapsByDragging)
            Toggle("Resize side-by-side windows together", isOn: $settings.resizesTogether)
        }
    }

    private var gestures: some View {
        Section("Gestures") {
            ForEach(SnapGesture.allCases) { gesture in
                Toggle(gesture.title, isOn: Binding(
                    get: { settings.gestures.contains(gesture) },
                    set: { isOn in
                        if isOn { settings.gestures.insert(gesture) } else { settings.gestures.remove(gesture) }
                    }
                ))
            }
        }
        .disabled(!settings.snapsByDragging)
    }

    private var shortcuts: some View {
        Section("Shortcuts") {
            LabeledContent("Modifier keys") {
                HStack(spacing: 6) {
                    ForEach(Self.modifierKeys, id: \.flag) { key in
                        Toggle(isOn: modifierBinding(key.flag)) {
                            Text(verbatim: key.symbol)
                                .frame(minWidth: 18)
                        }
                        .toggleStyle(.button)
                        .help(key.name)
                    }
                }
            }
            ForEach(SnapAction.allCases) { action in
                LabeledContent {
                    Text(verbatim: settings.shortcut(for: action).displayString)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } label: {
                    Label(action.title, systemImage: action.symbol)
                }
            }
        }
    }

    /// One modifier on or off. Control, Option or Command must stay on, so a shortcut can't
    /// take over typing.
    private func modifierBinding(_ flag: Int) -> Binding<Bool> {
        let required = UInt32(controlKey | optionKey | cmdKey)
        return Binding(
            get: { settings.modifiers & UInt32(flag) != 0 },
            set: { isOn in
                let changed = isOn ? settings.modifiers | UInt32(flag) : settings.modifiers & ~UInt32(flag)
                if changed & required != 0 { settings.modifiers = changed }
            }
        )
    }
}
