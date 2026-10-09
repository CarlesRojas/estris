import AppKit
import Combine
import IOKit.pwr_mgt
import SwiftUI

/// The Keep Awake utility: while on, stops the Mac and its display from sleeping when idle,
/// for as long as chosen for the current power source (power adapter or battery), then turns
/// itself off. The time counts from when it was turned on; plugging in or out switches to the
/// other source's choice. Owns everything it needs, so the app only has to create it and call
/// `start()`.
@MainActor
final class KeepAwake {
    let settings = KeepAwakeSettings()
    let status = KeepAwakeStatus()
    private let appLog: AppLog
    private lazy var power = PowerSource { [weak self] in self?.apply() }
    private var observers: Set<AnyCancellable> = []
    private var assertion: IOPMAssertionID?
    private var startedAt: Date?
    private var timer: Timer?

    init(log: AppLog) {
        appLog = log
    }

    func start() {
        power.start()
        // Published values arrive before the property changes; applying on the next turn of
        // the run loop reads the new ones.
        settings.$isEnabled.map { _ in () }
            .merge(with: settings.$onPower.map { _ in () }, settings.$onBattery.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.apply() }
            .store(in: &observers)
    }

    /// The pane shown for this utility in Settings.
    func settingsPane() -> some View {
        KeepAwakePane(settings: settings, status: status)
    }

    private func apply() {
        timer?.invalidate()
        timer = nil
        status.isOnBattery = PowerSource.isOnBattery
        guard settings.isEnabled else {
            startedAt = nil
            release()
            status.state = .off
            return
        }
        let started = startedAt ?? Date()
        startedAt = started
        let duration = status.isOnBattery ? settings.onBattery : settings.onPower
        switch duration.seconds {
        case nil:
            hold()
            status.state = .indefinitely
        case 0?:
            release()
            status.state = .paused
        case let seconds?:
            let end = started.addingTimeInterval(seconds)
            guard end > Date() else {
                // Time is up: turn the switch off, which releases it.
                settings.isEnabled = false
                return
            }
            hold()
            status.state = .until(end)
            timer = Timer.scheduledTimer(withTimeInterval: end.timeIntervalSinceNow, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            }
        }
    }

    private func hold() {
        guard assertion == nil else { return }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "PasteRing Keep Awake" as CFString,
            &id
        )
        if result == kIOReturnSuccess {
            assertion = id
        } else {
            log("can't keep the Mac awake (error \(result))")
        }
    }

    private func release() {
        guard let assertion else { return }
        IOPMAssertionRelease(assertion)
        self.assertion = nil
    }

    private func log(_ message: String) {
        appLog.record(message, source: "Keep Awake")
    }
}
