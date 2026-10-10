import AppKit
import SwiftUI

/// The Window Snapping settings pane: the on/off switch, then dragging, Arrange All, gestures
/// and the shortcuts on one page.
struct WindowSnappingPane: View {
    /// What it needs, for its Permissions section and the prompt when it's turned on.
    static let permissions: [PermissionUse] = [
        PermissionUse(permission: .accessibility, reason: "Only to move and resize windows.", without: "Without it, Window Snapping can't do anything."),
    ]

    @ObservedObject var settings: WindowSnappingSettings
    /// macOS's own ⌃⌥ shortcuts, by key; read again when PasteRing comes back from System Settings.
    @State private var systemShortcuts = SystemShortcuts.owners(flags: SnapKeys.systemFlags)

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
                arrangeAll
                gestures
                shortcuts
                Section {
                    Button("Reset to Defaults") { settings.reset() }
                }
            }
            .formStyle(.grouped)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                systemShortcuts = SystemShortcuts.owners(flags: SnapKeys.systemFlags)
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

    private var arrangeAll: some View {
        Section("Auto Arrange All Windows") {
            Toggle("Share the screen evenly among all its windows with a shortcut", isOn: $settings.arrangesAll)
            shortcutRow(id: SnapKeys.arrangeAllID, title: String(localized: "Arrange All Windows")) {
                Image(systemName: "square.grid.2x2")
            }
            .disabled(!settings.arrangesAll)
        }
    }

    private var shortcuts: some View {
        Section("Shortcuts") {
            ForEach(SnapAction.allCases) { action in
                shortcutRow(id: action.rawValue, title: action.title) {
                    SnapActionIcon(action: action)
                }
            }
        }
    }

    /// A shortcut: ⌃⌥ and a menu to pick its key, with what else uses it right below.
    private func shortcutRow<Icon: View>(id: String, title: String, @ViewBuilder icon: () -> Icon) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent {
                HStack(spacing: 4) {
                    Text(verbatim: "⌃⌥")
                        .foregroundStyle(.secondary)
                    Picker(title, selection: Binding(
                        get: { settings.keyCode(for: id) },
                        set: { code in
                            if code == SnapKeys.defaultCode(for: id) { settings.keyCodes[id] = nil } else { settings.keyCodes[id] = code }
                        }
                    )) {
                        ForEach(SnapKeys.all) { key in
                            Text(verbatim: key.label).tag(key.code)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            } label: {
                Label { Text(title) } icon: { icon() }
            }
            if id != SnapKeys.arrangeAllID || settings.arrangesAll {
                conflicts(for: id)
            }
        }
    }

    /// The other Window Snapping shortcuts on the same key, and the macOS one, if any.
    @ViewBuilder
    private func conflicts(for id: String) -> some View {
        let code = settings.keyCode(for: id)
        // In priority order: the first one with a key gets it.
        let sharing = SnapKeys.ids.filter { other in
            settings.keyCode(for: other) == code && (other != SnapKeys.arrangeAllID || settings.arrangesAll)
        }
        if sharing.count > 1, let first = sharing.first {
            if first == id {
                let names = sharing.dropFirst().map(title(for:))
                warning(String(localized: "Also set for \(ListFormatter.localizedString(byJoining: names)). This one takes priority."))
            } else {
                warning(String(localized: "Also set for \(title(for: first)), which takes priority, so this one won't work."))
            }
        }
        if let owner = systemShortcuts[CGKeyCode(code)] {
            HStack(alignment: .top, spacing: 10) {
                warning(owner == SystemShortcuts.selectNextInputSource
                    ? String(localized: "macOS uses this shortcut to switch the keyboard's input source. Turn it off to use it here: Keyboard Shortcuts > Input Sources > Select next source in Input menu.")
                    : String(localized: "macOS already uses this shortcut. Turn it off in Keyboard Shortcuts to use it here, or pick another key."))
                Spacer(minLength: 8)
                Button("Open Keyboard Shortcuts") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                }
            }
        }
    }

    private func title(for id: String) -> String {
        SnapAction(rawValue: id)?.title ?? String(localized: "Arrange All Windows")
    }

    private func warning(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A snap action's icon: its SF Symbol, or for the center third, a frame with a bar in its middle
/// third, matching the left and right third symbols.
struct SnapActionIcon: View {
    let action: SnapAction

    var body: some View {
        if action == .centerThird {
            Image(systemName: "rectangle")
                .overlay {
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: proxy.size.width * 0.03)
                            .frame(width: proxy.size.width * 0.2, height: proxy.size.height * 0.6)
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    }
                }
        } else {
            Image(systemName: action.symbol)
        }
    }
}
