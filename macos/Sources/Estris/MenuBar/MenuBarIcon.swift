import AppKit
import SwiftUI

/// The icons to choose from for the menu bar: Estris's own first, then its other drawings,
/// then common symbols. They are template images, so macOS draws them in the menu bar's
/// colour (white on a dark one), unless a colour is chosen for them.
enum MenuBarIcon {
    /// Estris's own icon, the default: the bento box, as on the app icon.
    static let app = "app"

    /// Drawn here rather than SF Symbols, on a 24-point grid.
    private static let drawn = [app, "estris.drawers", "estris.dots", "estris.sliders"]

    /// 13 per row in Settings, four rows.
    static let all: [String] = drawn + [
        "doc.on.clipboard",
        "star.fill", "heart.fill", "flame.fill", "leaf.fill", "sun.max.fill", "moon.fill",
        "moon.stars.fill", "cloud.fill", "cloud.rain.fill", "bolt.fill", "snowflake", "drop.fill",
        "sparkles", "wand.and.stars", "crown.fill", "diamond.fill",
        "circle.fill", "square.fill", "triangle.fill", "hexagon.fill", "seal.fill", "flag.fill",
        "bookmark.fill", "bell.fill", "tag.fill", "paperclip", "pin.fill", "pencil",
        "scissors", "paintbrush.fill", "hammer.fill", "gearshape.fill",
        "cube.fill", "puzzlepiece.fill", "gamecontroller.fill", "music.note", "headphones", "camera.fill",
        "lightbulb.fill", "key.fill", "lock.fill", "house.fill", "globe", "airplane",
        "pawprint.fill", "tortoise.fill", "hare.fill",
    ]

    /// In the menu bar's own colour, or in `color` when one is chosen.
    static func image(for icon: String, color: NSColor? = nil) -> NSImage? {
        if drawn.contains(icon) {
            return drawnImage(icon, size: 18, color: color)
        }
        var image = NSImage(systemSymbolName: icon, accessibilityDescription: "Estris")
            ?? drawnImage(app, size: 18, color: color)
        if let color {
            image = image?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))
            image?.isTemplate = false
        } else {
            image?.isTemplate = true
        }
        return image
    }

    /// For the grid in Settings, at the size and in the colour around it.
    @ViewBuilder
    static func view(for icon: String, size: CGFloat) -> some View {
        if drawn.contains(icon), let image = drawnImage(icon, size: size, color: nil) {
            Image(nsImage: image)
                .renderingMode(.template)
        } else {
            Image(systemName: icon)
                .font(.system(size: size * 0.78))
        }
    }

    /// One of Estris's drawings, a template image unless a colour is given.
    private static func drawnImage(_ icon: String, size: CGFloat, color: NSColor?) -> NSImage? {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            let scale = NSAffineTransform()
            scale.scale(by: size / 24)
            scale.concat()
            (color ?? .black).set()
            draw(icon)
            return true
        }
        image.isTemplate = color == nil
        image.accessibilityDescription = "Estris"
        return image
    }

    /// Fills and strokes in the current colour, on a 24 by 24 grid with y down.
    private static func draw(_ icon: String) {
        func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, radius: CGFloat) -> NSBezierPath {
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height), xRadius: radius, yRadius: radius)
        }
        func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) -> NSBezierPath {
            NSBezierPath(ovalIn: NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }
        func line(_ points: [(CGFloat, CGFloat)], in path: NSBezierPath) {
            path.move(to: NSPoint(x: points[0].0, y: points[0].1))
            for point in points.dropFirst() { path.line(to: NSPoint(x: point.0, y: point.1)) }
        }
        func stroke(_ path: NSBezierPath) {
            path.lineWidth = 2
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }

        switch icon {
        case "estris.drawers":
            // A chest of two drawers, each with its handle.
            stroke(rect(3, 4, 18, 16, radius: 3))
            let lines = NSBezierPath()
            line([(3, 12), (21, 12)], in: lines)
            line([(10, 8), (14, 8)], in: lines)
            line([(10, 16), (14, 16)], in: lines)
            stroke(lines)
        case "estris.dots":
            // Six dots in a ring.
            for step in 0..<6 {
                let angle = (CGFloat(step) * 60 - 90) * .pi / 180
                circle(12 + 7.5 * cos(angle), 12 + 7.5 * sin(angle), 2.3).fill()
            }
        case "estris.sliders":
            // Three sliders, set at different points.
            let lines = NSBezierPath()
            for y: CGFloat in [6, 12, 18] { line([(3, y), (21, y)], in: lines) }
            stroke(lines)
            circle(8, 6, 2.6).fill()
            circle(16, 12, 2.6).fill()
            circle(11, 18, 2.6).fill()
        default:
            // The bento box: one tall compartment and two small ones.
            rect(3, 3, 8, 18, radius: 2).fill()
            rect(13, 3, 8, 8, radius: 2).fill()
            rect(13, 13, 8, 8, radius: 2).fill()
        }
    }
}
