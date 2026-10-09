import AppKit
import Combine
import SwiftUI

/// The Color Picker utility: a shortcut shows macOS's color sampler, a loupe by the pointer
/// with the color under it; a click copies that color in the chosen format and shows it in a
/// pill by the pointer for a moment. Owns everything it needs, so the app only has to create
/// it and call `start()`.
@MainActor
final class ScreenColorPicker {
    let settings = ColorPickerSettings()
    private let pill = CopiedPill()
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
        NSColorSampler().show { [weak self] color in
            MainActor.assumeIsolated {
                self?.isPicking = false
                if let color { self?.copy(color) }
            }
        }
    }

    private func copy(_ color: NSColor) {
        let text = settings.format.string(for: color, hashPrefix: settings.hashPrefix)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        pill.show(color, text: text)
    }
}
