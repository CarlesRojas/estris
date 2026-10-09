import AppKit
import Combine
import SwiftUI

/// The Mouse utility: a trackpad tap for the middle click, and pointer speed.
/// Owns everything it needs, so the app only has to create it and call `start()`.
@MainActor
final class Mouse {
    let settings = MouseSettings()
    private let middleClick: MiddleClick
    private let appLog: AppLog
    private lazy var devices = DeviceWatcher { [weak self] in self?.devicesChanged() }
    private var observers: Set<AnyCancellable> = []

    init(log: AppLog) {
        appLog = log
        middleClick = MiddleClick(log: log)
    }

    func start() {
        devices.start()
        // Published values arrive before the property changes, so use the values passed in.
        settings.$middleClick
            .removeDuplicates()
            .sink { [weak self] gesture in self?.middleClick.listen(fingers: gesture.fingers) }
            .store(in: &observers)
        settings.$setsMouseSpeed.combineLatest(settings.$mouseSpeed)
            .sink { [weak self] sets, speed in self?.applySpeed(sets ? speed : nil, to: .mouse) }
            .store(in: &observers)
        settings.$setsTrackpadSpeed.combineLatest(settings.$trackpadSpeed)
            .sink { [weak self] sets, speed in self?.applySpeed(sets ? speed : nil, to: .trackpad) }
            .store(in: &observers)
    }

    /// The pane shown for this utility in Settings.
    func settingsPane() -> some View {
        MousePane(settings: settings)
    }

    private func applySpeed(_ speed: Double?, to device: PointerSpeed.Device) {
        if !PointerSpeed.apply(speed, to: device) {
            appLog.record("can't set the \(device == .mouse ? "mouse" : "trackpad") speed", source: "Mouse")
        }
    }

    /// A device connected or the Mac woke: macOS has reset the speeds and trackpads need
    /// listening to again.
    private func devicesChanged() {
        middleClick.listen(fingers: settings.middleClick.fingers)
        if settings.setsMouseSpeed { applySpeed(settings.mouseSpeed, to: .mouse) }
        if settings.setsTrackpadSpeed { applySpeed(settings.trackpadSpeed, to: .trackpad) }
    }
}
