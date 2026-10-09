import AppKit
import Combine
import SwiftUI

/// The Auto Quit utility: quits an app when its last window closes.
/// Owns everything it needs, so the app only has to create it and call `start()`.
@MainActor
final class AutoQuit {
    let settings = AutoQuitSettings()
    let activity = AutoQuitActivity()
    private let watcher: WindowWatcher
    private var observers: Set<AnyCancellable> = []

    init() {
        watcher = WindowWatcher(settings: settings, activity: activity)
    }

    func start() {
        // Published values arrive before the property changes, so use the value passed in.
        settings.$isEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                if enabled {
                    self?.watcher.start()
                } else {
                    self?.watcher.stop()
                }
            }
            .store(in: &observers)
    }

    /// The pane shown for this utility in Settings.
    func settingsPane() -> some View {
        AutoQuitPane(settings: settings, activity: activity)
    }
}
