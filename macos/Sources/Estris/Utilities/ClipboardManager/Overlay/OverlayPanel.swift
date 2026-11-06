import AppKit
import SwiftUI

/// Lets the first click on an overlay element act right away; the panel never becomes key.
final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Transparent panel covering the whole screen so it receives scroll events wherever
/// the pointer is, keeping them from scrolling the app underneath.
final class OverlayPanel: NSPanel {
    var onScroll: ((NSEvent) -> Void)?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func configure() {
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    func present(on screen: NSScreen?) {
        if let screen {
            setFrame(screen.frame, display: true)
        }
        orderFrontRegardless()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel {
            onScroll?(event)
        } else {
            super.sendEvent(event)
        }
    }
}
