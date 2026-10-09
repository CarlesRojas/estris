import AppKit
import Combine
import IOKit.pwr_mgt
import SwiftUI

/// The Keep Awake utility: while on, keeps the Mac and its display awake until it has been
/// idle for as long as chosen for the current power source (power adapter or battery). Idle
/// means no mouse, keyboard or trackpad input and nothing else keeping the display on (a
/// playing video does); any of those starts the count again. Once idle for that long it puts
/// the Mac to sleep, and holds again when the Mac wakes or is used. Owns
/// everything it needs, so the app only has to create it and call `start()`.
@MainActor
final class KeepAwake {
    /// How often to look again while another app keeps the display on, in case the change
    /// notice below doesn't arrive.
    private static let otherHolderRecheck: TimeInterval = 5
    /// What macOS posts when any app starts or stops keeping the Mac or display awake.
    private static let assertionNotices = [
        "com.apple.system.powermanagement.assertions",
        "com.apple.system.powermanagement.assertions.anychange",
    ]

    let settings = KeepAwakeSettings()
    let status = KeepAwakeStatus()
    private let appLog: AppLog
    private lazy var power = PowerSource { [weak self] in self?.evaluate() }
    private var observers: Set<AnyCancellable> = []
    private var wakeTokens: [NSObjectProtocol] = []
    /// The apps last seen keeping the display on, to log when that changes.
    private var displayHolders: [String] = []
    private var assertion: IOPMAssertionID?
    private var timer: Timer?
    /// Watches for input after letting go, to hold again when the Mac is used.
    private var activityMonitor: Any?

    init(log: AppLog) {
        appLog = log
    }

    func start() {
        power.start()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.assertionNotices {
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                observer,
                assertionsChanged,
                name as CFString,
                nil,
                .deliverImmediately
            )
        }
        let center = NSWorkspace.shared.notificationCenter
        wakeTokens = [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // Waking counts as activity, so the count starts over instead of the
                    // Mac being put straight back to sleep.
                    self?.status.lastWake = Date()
                    self?.evaluate()
                }
            }
        }
        // Published values arrive before the property changes; applying on the next turn of
        // the run loop reads the new ones.
        settings.$isEnabled.map { _ in () }
            .merge(with: settings.$onPower.map { _ in () }, settings.$onBattery.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.evaluate() }
            .store(in: &observers)
    }

    /// The pane shown for this utility in Settings.
    func settingsPane() -> some View {
        KeepAwakePane(settings: settings, status: status)
    }

    /// Decides whether to hold the Mac awake now, and when to look again.
    private func evaluate() {
        timer?.invalidate()
        timer = nil
        stopWatchingActivity()
        status.isOnBattery = PowerSource.isOnBattery
        guard settings.isEnabled else {
            release()
            status.state = .off
            return
        }
        let duration = status.isOnBattery ? settings.onBattery : settings.onPower
        status.limit = duration.seconds
        guard let limit = duration.seconds else {
            hold()
            status.state = .indefinitely
            return
        }
        guard limit > 0 else {
            release()
            status.state = .paused
            return
        }

        let holders = Self.appsKeepingDisplayOn()
        if holders != displayHolders {
            log(holders.isEmpty ? "no other app keeps the display on" : "display kept on by \(holders.joined(separator: ", "))")
            displayHolders = holders
        }
        let otherHolderActive = !holders.isEmpty
        if status.otherAppKeepsDisplayOn && !otherHolderActive { status.otherHolderEndedAt = Date() }
        status.otherAppKeepsDisplayOn = otherHolderActive
        if otherHolderActive {
            hold()
            status.state = .active
            lookAgain(in: Self.otherHolderRecheck)
            return
        }

        let idle = status.idleTime
        if idle < limit {
            hold()
            status.state = .active
            lookAgain(in: limit - idle)
        } else {
            release()
            let wasCounting = status.state == .active
            status.state = .idle
            watchForActivity()
            // The time is up: sleep now rather than waiting for macOS's own timers.
            if wasCounting { sleepNow() }
        }
    }

    /// Puts the Mac to sleep, as macOS's own `pmset sleepnow` does.
    private func sleepNow() {
        log("idle for the chosen time, sleeping")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["sleepnow"]
        do {
            try process.run()
        } catch {
            log("can't put the Mac to sleep: \(error.localizedDescription)")
        }
    }

    private func lookAgain(in seconds: TimeInterval) {
        timer = Timer.scheduledTimer(withTimeInterval: max(seconds, 1), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
    }

    private func watchForActivity() {
        guard activityMonitor == nil else { return }
        activityMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
    }

    private func stopWatchingActivity() {
        if let activityMonitor { NSEvent.removeMonitor(activityMonitor) }
        activityMonitor = nil
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

    /// The other apps keeping the display on, as video players do while playing, by name.
    private static func appsKeepingDisplayOn() -> [String] {
        var byProcess: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
              let assertions = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return [] }
        let displayTypes: Set<String> = [
            kIOPMAssertionTypePreventUserIdleDisplaySleep as String,
            kIOPMAssertionTypeNoDisplaySleep as String,
        ]
        return assertions.compactMap { pid, list -> String? in
            guard pid.int32Value != getpid(),
                  list.contains(where: { ($0[kIOPMAssertionTypeKey as String] as? String).map(displayTypes.contains) ?? false })
            else { return nil }
            return NSRunningApplication(processIdentifier: pid.int32Value)?.localizedName ?? "process \(pid)"
        }
        .sorted()
    }

    private func log(_ message: String) {
        appLog.record(message, source: "Keep Awake")
    }

    fileprivate func assertionsDidChange() {
        evaluate()
    }
}

/// Plain C function for the notice that power assertions changed; Keep Awake comes back
/// through the observer pointer. Darwin notices are delivered on the main thread.
private func assertionsChanged(
    _ center: CFNotificationCenter?,
    _ observer: UnsafeMutableRawPointer?,
    _ name: CFNotificationName?,
    _ object: UnsafeRawPointer?,
    _ userInfo: CFDictionary?
) {
    guard let observer else { return }
    let keepAwake = Unmanaged<KeepAwake>.fromOpaque(observer).takeUnretainedValue()
    DispatchQueue.main.async {
        MainActor.assumeIsolated { keepAwake.assertionsDidChange() }
    }
}
