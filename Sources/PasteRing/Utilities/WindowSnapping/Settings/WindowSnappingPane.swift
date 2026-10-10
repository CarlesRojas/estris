import AppKit
import SwiftUI

/// The Window Snapping settings pane: the on/off switch, then dragging, gestures and the
/// shortcuts on one page.
struct WindowSnappingPane: View {
    /// What it needs, for its Permissions section and the prompt when it's turned on.
    static let permissions: [PermissionUse] = [
        PermissionUse(permission: .accessibility, reason: "Only to move and resize windows.", without: "Without it, Window Snapping can't do anything."),
    ]

    @ObservedObject var settings: WindowSnappingSettings
    /// Read again when PasteRing comes back from System Settings.
    @State private var arrangeShortcutTaken = WindowArranger.isShortcutTaken

    var body: some View {
        VStack(spacing: 0) {
            UtilityHeader(
                title: SettingsPane.windowSnapping.title,
                symbol: SettingsPane.windowSnapping.symbol,
                summary: "Snap windows to halves, corners and thirds with shortcuts or by dragging them to a screen edge.",
                isOn: $settings.isEnabled,
                permissions: Self.permissions
            )

            Form {
                PermissionsSection(uses: WindowSnappingPane.permissions)
                dragging
                gestures
                shortcuts
                Section {
                    Button("Reset to Defaults") { settings.reset() }
                }
            }
            .formStyle(.grouped)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                arrangeShortcutTaken = WindowArranger.isShortcutTaken
            }
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
                    // No step: it would draw a tick mark for every point.
                    Slider(
                        value: Binding(get: { settings.edgeArea }, set: { settings.edgeArea = $0.rounded() }),
                        in: WindowSnappingSettings.edgeAreaRange
                    )
                        .frame(width: 200)
                    Text("\(Int(settings.edgeArea)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }
            }
            .disabled(!settings.snapsByDragging)
            Toggle("Resize side-by-side windows together", isOn: $settings.resizesTogether)
            Toggle(isOn: $settings.fillsSpace) {
                Text("Fill the space next to other windows")
                Text("Press a shortcut again for the exact size, or hold ⌘ while dragging.")
            }
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
            ForEach(SnapAction.allCases) { action in
                LabeledContent {
                    Text(verbatim: action.shortcut.displayString)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } label: {
                    Label(action.title, systemImage: action.symbol)
                }
            }
            Toggle(isOn: $settings.arrangesAll) {
                HStack {
                    Label("Arrange All Windows", systemImage: "square.grid.2x2")
                    Spacer()
                    Text(verbatim: WindowArranger.shortcut.displayString)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if settings.arrangesAll && arrangeShortcutTaken {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("macOS uses ⌃⌥Space to switch the keyboard's input source, so Arrange All Windows won't work until that shortcut is turned off: Keyboard Shortcuts > Input Sources > Select next source in Input menu.")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Open Keyboard Shortcuts") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                    }
                }
            }
        }
    }
}
