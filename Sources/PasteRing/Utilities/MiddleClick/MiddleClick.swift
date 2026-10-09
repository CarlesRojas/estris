import AppKit
import Combine
import SwiftUI

/// The Middle Click utility: a trackpad tap with three or four fingers clicks the middle
/// button. Owns everything it needs, so the app only has to create it and call `start()`.
@MainActor
final class MiddleClick {
    let settings = MiddleClickSettings()
    private let listener: TapListener
    private lazy var devices = DeviceWatcher { [weak self] in self?.listen() }
    private var observers: Set<AnyCancellable> = []

    init(log: AppLog) {
        listener = TapListener(log: log)
    }

    func start() {
        devices.start()
        // Published values arrive before the property changes, so use the values passed in.
        settings.$isEnabled.combineLatest(settings.$fingers)
            .sink { [weak self] enabled, fingers in self?.listener.listen(fingers: enabled ? fingers.rawValue : 0) }
            .store(in: &observers)
    }

    /// The pane shown for this utility in Settings.
    func settingsPane() -> some View {
        MiddleClickPane(settings: settings)
    }

    /// A trackpad connected or the Mac woke: trackpads need listening to again.
    private func listen() {
        listener.listen(fingers: settings.isEnabled ? settings.fingers.rawValue : 0)
    }
}
