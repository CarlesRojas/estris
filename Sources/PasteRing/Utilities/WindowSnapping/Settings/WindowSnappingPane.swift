import SwiftUI

/// The Window Snapping settings pane: the on/off switch, then Settings and Shortcuts tabs.
struct WindowSnappingPane: View {
    private enum Tab: String, CaseIterable {
        case settings = "Settings"
        case shortcuts = "Shortcuts"
    }

    @ObservedObject var settings: WindowSnappingSettings
    @State private var tab = Tab.settings

    var body: some View {
        UtilityPane(
            pane: .windowSnapping,
            summary: "Snap windows to halves, corners and thirds with shortcuts or by dragging them to a screen edge.",
            isOn: $settings.isEnabled,
            tab: $tab
        ) { tab in
            switch tab {
            case .settings:
                settingsForm
            case .shortcuts:
                shortcutsForm
            }
        }
    }

    private var settingsForm: some View {
        Form {
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
        .formStyle(.grouped)
        .settingsPage()
    }

    private var shortcutsForm: some View {
        Form {
            ForEach(SnapAction.Group.allCases, id: \.self) { group in
                Section(group.title) {
                    ForEach(SnapAction.allCases.filter { $0.group == group }) { action in
                        LabeledContent {
                            ShortcutRecorder(shortcut: Binding(
                                get: { settings.shortcut(for: action) },
                                set: { settings.shortcuts[action] = $0 }
                            ))
                        } label: {
                            Label(action.title, systemImage: action.symbol)
                        }
                    }
                }
            }
            Section {
                Button("Reset Shortcuts to Defaults") {
                    settings.resetShortcuts()
                }
            }
        }
        .formStyle(.grouped)
        .settingsPage()
    }
}
