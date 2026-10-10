import Foundation
import IOKit.ps

/// Whether the Mac runs on battery, and a callback when that changes (plugging in or out).
@MainActor
final class PowerSource {
    private let onChange: () -> Void
    private var source: CFRunLoopSource?

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    static var isOnBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue()
        else { return false }
        return (type as String) == kIOPMBatteryPowerKey
    }

    func start() {
        guard source == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let created = IOPSNotificationCreateRunLoopSource(powerSourceChanged, context)?.takeRetainedValue() else { return }
        source = created
        CFRunLoopAddSource(CFRunLoopGetMain(), created, .commonModes)
    }

    fileprivate func changed() {
        onChange()
    }
}

/// Plain C function for IOKit; the watcher comes back through the context. Runs on the main
/// run loop, where the source is scheduled.
private func powerSourceChanged(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let source = Unmanaged<PowerSource>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { source.changed() }
}
