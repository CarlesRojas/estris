import AppKit
import Combine
import SwiftUI

/// The Rounded Corners utility: while on, paints the corners of every screen black, as if the
/// screens themselves had rounded corners. Each corner is a small window that lets clicks
/// through, above everything (menu bar, Dock and full screen apps included) and on every
/// Space. Owns everything it needs, so the app only has to create it and call `start()`.
@MainActor
final class RoundedCorners {
    let settings = RoundedCornersSettings()
    private var windows: [CornerWindow] = []
    private var observers: Set<AnyCancellable> = []
    private var screenToken: NSObjectProtocol?

    func start() {
        // Screens added, removed or rearranged, or their resolution changed.
        screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        // Published values arrive before the property changes; applying on the next turn of
        // the run loop reads the new ones.
        settings.$isEnabled.map { _ in () }
            .merge(with: settings.$radius.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.update() }
            .store(in: &observers)
    }

    /// The pane shown for this utility in Settings.
    func settingsPane() -> some View {
        RoundedCornersPane(settings: settings)
    }

    /// One window per corner of every screen while on, none while off. Windows are kept and
    /// moved rather than made again, so dragging the radius slider stays smooth.
    private func update() {
        let corners = settings.isEnabled
            ? NSScreen.screens.flatMap { screen in ScreenCorner.allCases.map { (screen.frame, $0) } }
            : []
        while windows.count > corners.count {
            windows.removeLast().close()
        }
        while windows.count < corners.count {
            windows.append(CornerWindow())
        }
        for (window, (screen, corner)) in zip(windows, corners) {
            window.show(corner, of: screen, radius: settings.radius)
        }
    }
}

private enum ScreenCorner: CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    /// A square of the given side in this corner of the screen.
    func rect(side: CGFloat, in screen: NSRect) -> NSRect {
        let x = self == .topLeft || self == .bottomLeft ? screen.minX : screen.maxX - side
        let y = self == .bottomLeft || self == .bottomRight ? screen.minY : screen.maxY - side
        return NSRect(x: x, y: y, width: side, height: side)
    }
}

/// A click-through window painting one corner of a screen black: everything in it outside the
/// screen's rounded outline.
private final class CornerWindow: NSWindow {
    private let shape = CAShapeLayer()

    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Left out of screenshots and recordings, where real screen corners wouldn't show.
        sharingType = .none
        let view = NSView()
        view.wantsLayer = true
        shape.fillColor = NSColor.black.cgColor
        shape.fillRule = .evenOdd
        view.layer?.addSublayer(shape)
        contentView = view
    }

    /// Kept exactly where it is put: macOS would push a window off the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    func show(_ corner: ScreenCorner, of screen: NSRect, radius: Double) {
        let radius = CGFloat(radius)
        // A continuous corner, like a window's, starts bending about 1.53 radii from the
        // corner; the window covers a little more.
        let frame = corner.rect(side: ceil(radius * 2), in: screen)
        setFrame(frame, display: false)
        let outline = screen.offsetBy(dx: -frame.minX, dy: -frame.minY)
        let path = CGMutablePath()
        path.addRect(CGRect(origin: .zero, size: frame.size))
        path.addPath(RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: outline).cgPath)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.frame = CGRect(origin: .zero, size: frame.size)
        shape.path = path
        CATransaction.commit()
        orderFrontRegardless()
    }
}
