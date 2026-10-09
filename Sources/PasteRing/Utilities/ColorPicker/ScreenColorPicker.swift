import AppKit
import Combine
import SwiftUI

/// The Color Picker utility: a shortcut shows a loupe at the pointer with a label under it,
/// the color and its value in the chosen format, following the pointer; clicking copies it
/// and the label says Copied for a moment. Without the Screen Recording permission it falls
/// back to macOS's own sampler, and the label only shows once picked. Owns everything it needs, so the app only has to create it and
/// call `start()`.
@MainActor
final class ScreenColorPicker {
    let settings = ColorPickerSettings()
    private let hud = PickerHUD()
    private var session: PickerSession?
    private var hotKey: UInt32?
    private var observers: Set<AnyCancellable> = []
    private var isPicking = false

    func start() {
        // Published values arrive before the property changes; applying on the next turn of
        // the run loop reads the new ones.
        settings.$isEnabled.map { _ in () }
            .merge(with: settings.$shortcut.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.apply() }
            .store(in: &observers)
    }

    /// The pane shown for this utility in Settings.
    func settingsPane() -> some View {
        ColorPickerPane(settings: settings)
    }

    private func apply() {
        if let hotKey { HotKeyCenter.shared.unregister(hotKey) }
        hotKey = nil
        guard settings.isEnabled else { return }
        let shortcut = settings.shortcut
        hotKey = HotKeyCenter.shared.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
            self?.pick()
        }
    }

    private func pick() {
        guard !isPicking else { return }
        isPicking = true
        guard ScreenSampler.isAllowed else {
            // Without Screen Recording the value can't follow the pointer: use macOS's own
            // sampler, and show the label once picked.
            ScreenSampler.requestAccess()
            NSColorSampler().show { [weak self] color in
                MainActor.assumeIsolated {
                    self?.isPicking = false
                    if let color { self?.copy(color, at: NSEvent.mouseLocation) }
                }
            }
            return
        }
        let session = PickerSession(hud: hud, format: { [settings] in settings.format.string(for: $0, hashPrefix: settings.hashPrefix) }) { [weak self] color, point in
            guard let self else { return }
            self.isPicking = false
            self.session = nil
            if let color { self.copy(color, at: point) } else { self.hud.hide() }
        }
        self.session = session
        session.begin()
    }

    private func copy(_ color: NSColor, at point: NSPoint) {
        let text = settings.format.string(for: color, hashPrefix: settings.hashPrefix)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        hud.showPicked(color, text: text, at: point)
    }
}
