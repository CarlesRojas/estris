import AppKit
import IOKit
import IOKit.hid

/// Calls back when an input device or trackpad connects, or the Mac wakes: new trackpads
/// aren't being listened to yet, and trackpads stop reporting touches after sleep.
@MainActor
final class DeviceWatcher {
    /// New devices take a moment to be ready after they appear, and several appear at once.
    private static let settleDelay: TimeInterval = 1

    private let onChange: () -> Void
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var wakeToken: NSObjectProtocol?
    private var pending: DispatchWorkItem?

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard port == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        IONotificationPortSetDispatchQueue(port, .main)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        // Built-in trackpads show up as multitouch devices rather than HID devices.
        for className in [kIOHIDDeviceKey, "AppleMultitouchDevice"] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching(className), deviceAdded, refcon, &iterator)
            guard result == KERN_SUCCESS else { continue }
            // Arms the notification; the devices already there need no call.
            Self.drain(iterator)
            iterators.append(iterator)
        }
        wakeToken = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleChange() }
        }
    }

    func stop() {
        for iterator in iterators { IOObjectRelease(iterator) }
        iterators = []
        if let port { IONotificationPortDestroy(port) }
        port = nil
        if let wakeToken { NSWorkspace.shared.notificationCenter.removeObserver(wakeToken) }
        wakeToken = nil
        pending?.cancel()
    }

    fileprivate func devicesAdded(_ iterator: io_iterator_t) {
        Self.drain(iterator)
        scheduleChange()
    }

    private func scheduleChange() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }

    private static func drain(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            IOObjectRelease(service)
        }
    }
}

/// Plain C function for IOKit; the watcher comes back through the refcon. Runs on the main
/// queue, where the notification port delivers.
private func deviceAdded(_ refcon: UnsafeMutableRawPointer?, _ iterator: io_iterator_t) {
    guard let refcon else { return }
    let watcher = Unmanaged<DeviceWatcher>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated {
        watcher.devicesAdded(iterator)
    }
}
