import AppKit
import ApplicationServices

/// Moves the windows next to one being resized, on a thread of its own: each Accessibility
/// call waits for the app to answer, so made on the main thread they would hold up the drag
/// and the preview. Only the latest frames are applied: when apps are slower than the pointer,
/// the steps in between are skipped instead of piling up.
final class NeighbourFollower: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Estris.NeighbourFollower", qos: .userInteractive)
    private let lock = NSLock()

    // Guarded by the lock.
    private var pending: [CGRect?]?
    private var isApplying = false

    // Only touched on the queue.
    private var windows: [AXUIElement] = []
    private var applied: [CGRect?] = []
    private var enhancedApps: [AXUIElement] = []

    /// Starts following these windows, with their frames now in Accessibility coordinates.
    /// Their apps' enhanced user interface, which animates every change and makes a window
    /// trail behind, is off until `end`.
    func begin(_ followed: [(window: AXUIElement, frame: CGRect)], pids: Set<pid_t>) {
        queue.async { [self] in
            windows = followed.map(\.window)
            applied = followed.map(\.frame)
            enhancedApps = pids.compactMap(AXWindow.turnOffEnhancedUserInterface(pid:))
        }
    }

    /// Moves each window to its frame, in the order given to `begin`; nil leaves it.
    func move(to frames: [CGRect?]) {
        lock.lock()
        pending = frames
        let starts = !isApplying
        isApplying = true
        lock.unlock()
        if starts { queue.async { [self] in drain() } }
    }

    /// Gives the apps back their enhanced user interface once the last frames are in.
    func end() {
        queue.async { [self] in
            enhancedApps.forEach(AXWindow.turnOnEnhancedUserInterface)
            windows = []
            applied = []
            enhancedApps = []
        }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let frames = pending else {
                isApplying = false
                lock.unlock()
                return
            }
            pending = nil
            lock.unlock()
            for (index, frame) in frames.enumerated() where index < windows.count {
                guard let frame, frame != applied[index] else { continue }
                AXWindow.place(windows[index], at: frame, from: applied[index])
                applied[index] = frame
            }
        }
    }
}
