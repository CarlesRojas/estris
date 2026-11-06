import AppKit
import ApplicationServices

/// Moves the windows next to one being resized, each on a thread of its own: an Accessibility
/// call waits for the app to lay itself out, so one after the other a slow app would hold up
/// the rest, and on the main thread the drag and the preview too. Only the latest frame is
/// applied: when an app is slower than the pointer, the steps in between are skipped instead of
/// piling up.
final class NeighbourFollower: @unchecked Sendable {
    /// Turns the apps' enhanced user interface off and on, which also waits for them.
    private let control = DispatchQueue(label: "Estris.NeighbourFollower", qos: .userInteractive)

    // Only touched on the main thread.
    private var workers: [Worker] = []

    // Only touched on the control queue.
    private var enhancedApps: [AXUIElement] = []

    /// Starts following these windows, with their frames now in Accessibility coordinates.
    /// Their apps' enhanced user interface, which animates every change and makes a window
    /// trail behind, is off until `end`.
    func begin(_ followed: [(window: AXUIElement, frame: CGRect)], pids: Set<pid_t>) {
        workers = followed.map { Worker(window: $0.window, frame: $0.frame) }
        control.async { [self] in
            enhancedApps = pids.compactMap(AXWindow.turnOffEnhancedUserInterface(pid:))
        }
    }

    /// Moves each window to its frame, in the order given to `begin`; nil leaves it.
    func move(to frames: [CGRect?]) {
        for (worker, frame) in zip(workers, frames) {
            if let frame { worker.move(to: frame) }
        }
    }

    /// Gives the apps back their enhanced user interface once the last frames are in.
    func end() {
        let finishing = workers
        workers = []
        control.async { [self] in
            finishing.forEach { $0.finish() }
            enhancedApps.forEach(AXWindow.turnOnEnhancedUserInterface)
            enhancedApps = []
        }
    }
}

/// One followed window: the latest frame asked for, and a queue applying it.
private final class Worker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Estris.NeighbourFollower.Window", qos: .userInteractive)
    private let window: AXUIElement
    private let lock = NSLock()

    // Guarded by the lock.
    private var pending: CGRect?
    private var isApplying = false

    // Only touched on the queue.
    private var applied: CGRect

    init(window: AXUIElement, frame: CGRect) {
        self.window = window
        applied = frame
    }

    func move(to frame: CGRect) {
        lock.lock()
        pending = frame
        let starts = !isApplying
        isApplying = true
        lock.unlock()
        if starts { queue.async { [self] in drain() } }
    }

    /// Waits for what was asked for to be applied.
    func finish() {
        queue.sync {}
    }

    private func drain() {
        while true {
            lock.lock()
            guard let frame = pending else {
                isApplying = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()
            if frame != applied {
                AXWindow.place(window, at: frame, from: applied)
                applied = frame
            }
        }
    }
}
