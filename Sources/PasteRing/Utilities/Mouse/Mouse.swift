import AppKit
import Combine
import SwiftUI

/// The Mouse utility: a trackpad tap for the middle click.
/// Owns everything it needs, so the app only has to create it and call `start()`.
@MainActor
final class Mouse {
    let settings = MouseSettings()
    private let middleClick: MiddleClick
    private lazy var devices = DeviceWatcher { [weak self] in self?.listen() }
    private var observers: Set<AnyCancellable> = []

    init(log: AppLog) {
        middleClick = MiddleClick(log: log)
    }

    func start() {
        devices.start()
        // Published values arrive before the property changes, so use the value passed in.
        settings.$middleClick
            .removeDuplicates()
            .sink { [weak self] gesture in self?.middleClick.listen(fingers: gesture.fingers) }
            .store(in: &observers)
    }

    /// The pane shown for this utility in Settings.
    func settingsPane() -> some View {
        MousePane(settings: settings)
    }

    /// A trackpad connected or the Mac woke: trackpads need listening to again.
    private func listen() {
        middleClick.listen(fingers: settings.middleClick.fingers)
    }
}
