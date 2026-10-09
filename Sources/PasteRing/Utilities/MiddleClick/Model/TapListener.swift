import AppKit

/// Clicks the middle button when the trackpad is tapped with the chosen number of fingers.
///
/// macOS has no setting for this, so it reads the trackpad's raw touches from the private
/// MultitouchSupport framework (loaded at run time, so PasteRing still runs if it ever goes
/// away) and posts the click itself, which needs Accessibility access.
@MainActor
final class TapListener {
    private let appLog: AppLog
    /// The devices being listened to; holding the list keeps them alive.
    private var devices: CFArray?

    init(log: AppLog) {
        appLog = log
    }

    /// Listens for a tap with `fingers` fingers, or stops listening when it is 0.
    func listen(fingers: Int) {
        stop()
        tapDetector.fingers = fingers
        guard fingers > 0 else { return }
        guard let api = MultitouchAPI.shared, let list = api.createList()?.takeRetainedValue() else {
            return log("can't read the trackpad's touches")
        }
        devices = list
        for index in 0..<CFArrayGetCount(list) {
            guard let device = CFArrayGetValueAtIndex(list, index) else { continue }
            let pointer = UnsafeMutableRawPointer(mutating: device)
            api.register(pointer, multitouchCallback)
            _ = api.start(pointer, 0)
        }
        log("listening for a \(fingers)-finger tap on \(CFArrayGetCount(list)) device(s)")
    }

    func stop() {
        guard let list = devices, let api = MultitouchAPI.shared else { return }
        for index in 0..<CFArrayGetCount(list) {
            guard let device = CFArrayGetValueAtIndex(list, index) else { continue }
            let pointer = UnsafeMutableRawPointer(mutating: device)
            api.unregister(pointer, multitouchCallback)
            _ = api.stop(pointer)
        }
        devices = nil
    }

    private func log(_ message: String) {
        appLog.record(message, source: "Middle Click")
    }
}

/// Spots a quick tap: the chosen number of fingers down together, barely moving, and all
/// lifted soon after. Fed from the touch thread, so it guards its state with a lock.
private final class TapDetector: @unchecked Sendable {
    /// Longest a tap may last, in seconds.
    private static let maximumDuration = 0.3
    /// How far a finger may move (in trackpad widths) and still be a tap rather than a swipe.
    private static let maximumTravel: Float = 0.04
    /// Bytes per touch in the framework's touch list, and where the read fields sit.
    private static let touchStride = 96
    private static let identifierOffset = 16
    private static let stateOffset = 20
    private static let positionOffset = 32

    private let lock = NSLock()
    private var _fingers = 0
    private var began: Double?
    private var mostFingers = 0
    private var moved = false
    private var origins: [Int32: SIMD2<Float>] = [:]

    var fingers: Int {
        get { locked { _fingers } }
        set { locked { _fingers = newValue; reset() } }
    }

    func handle(touches: UnsafeMutableRawPointer?, count: Int, timestamp: Double) {
        let isTap: Bool = locked {
            guard _fingers > 0 else { return false }
            var down = 0
            if let touches {
                for index in 0..<count {
                    let touch = touches + index * Self.touchStride
                    // 4 and 5 are a finger making and keeping contact; the rest are hovering or lifting.
                    let state = touch.load(fromByteOffset: Self.stateOffset, as: Int32.self)
                    guard state == 4 || state == 5 else { continue }
                    down += 1
                    let identifier = touch.load(fromByteOffset: Self.identifierOffset, as: Int32.self)
                    let position = SIMD2(
                        touch.load(fromByteOffset: Self.positionOffset, as: Float.self),
                        touch.load(fromByteOffset: Self.positionOffset + 4, as: Float.self)
                    )
                    if let origin = origins[identifier] {
                        let travel = position - origin
                        if (travel * travel).sum() > Self.maximumTravel * Self.maximumTravel { moved = true }
                    } else {
                        origins[identifier] = position
                    }
                }
            }
            if down > 0 {
                if began == nil { began = timestamp }
                mostFingers = max(mostFingers, down)
                return false
            }
            guard let start = began else { return false }
            let isTap = !moved && mostFingers == _fingers && timestamp - start <= Self.maximumDuration
            reset()
            return isTap
        }
        if isTap { Self.clickMiddleButton() }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func reset() {
        began = nil
        mostFingers = 0
        moved = false
        origins = [:]
    }

    private static func clickMiddleButton() {
        guard let location = CGEvent(source: nil)?.location else { return }
        for type in [CGEventType.otherMouseDown, .otherMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: .center)?
                .post(tap: .cghidEventTap)
        }
    }
}

private let tapDetector = TapDetector()

/// Called by MultitouchSupport on its own thread for every frame of touches.
private func multitouchCallback(
    _ device: UnsafeMutableRawPointer?,
    _ touches: UnsafeMutableRawPointer?,
    _ count: Int32,
    _ timestamp: Double,
    _ frame: Int32
) -> Int32 {
    tapDetector.handle(touches: touches, count: Int(count), timestamp: timestamp)
    return 0
}

/// The MultitouchSupport calls used, looked up at run time.
private struct MultitouchAPI {
    typealias Callback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

    let createList: @convention(c) () -> Unmanaged<CFArray>?
    let register: @convention(c) (UnsafeMutableRawPointer, Callback) -> Void
    let unregister: @convention(c) (UnsafeMutableRawPointer, Callback) -> Void
    let start: @convention(c) (UnsafeMutableRawPointer, Int32) -> Int32
    let stop: @convention(c) (UnsafeMutableRawPointer) -> Int32

    static let shared: MultitouchAPI? = {
        guard let library = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
              let createList = dlsym(library, "MTDeviceCreateList"),
              let register = dlsym(library, "MTRegisterContactFrameCallback"),
              let unregister = dlsym(library, "MTUnregisterContactFrameCallback"),
              let start = dlsym(library, "MTDeviceStart"),
              let stop = dlsym(library, "MTDeviceStop")
        else { return nil }
        return MultitouchAPI(
            createList: unsafeBitCast(createList, to: (@convention(c) () -> Unmanaged<CFArray>?).self),
            register: unsafeBitCast(register, to: (@convention(c) (UnsafeMutableRawPointer, Callback) -> Void).self),
            unregister: unsafeBitCast(unregister, to: (@convention(c) (UnsafeMutableRawPointer, Callback) -> Void).self),
            start: unsafeBitCast(start, to: (@convention(c) (UnsafeMutableRawPointer, Int32) -> Int32).self),
            stop: unsafeBitCast(stop, to: (@convention(c) (UnsafeMutableRawPointer) -> Int32).self)
        )
    }()
}
