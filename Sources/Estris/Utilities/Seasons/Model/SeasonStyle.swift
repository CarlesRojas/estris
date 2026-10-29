import AppKit

/// How one season's particles look and move.
struct SeasonStyle {
    /// Drawn particles to pick from, each a square image.
    let sprites: [CGImage]
    /// Side of a particle, in points.
    let size: ClosedRange<CGFloat>
    /// Speed it falls at in still air, in points per second.
    let fallSpeed: ClosedRange<CGFloat>
    /// How far it drifts side to side, as a speed, and how quickly it sways.
    let sway: CGFloat
    let swayRate: ClosedRange<CGFloat>
    /// Fastest it turns, in radians per second.
    let spin: CGFloat
    /// How quickly it takes the speed of the air around it: light things follow at once.
    let drag: CGFloat
    /// Particles started each second across a screen 1440 points wide.
    let rate: Double
    /// How thick it lies on a pile, as a part of its size.
    let thickness: CGFloat
    /// The steepest a pile gets: the most one column (3 points wide) stands above the next
    /// before what lands on it rolls down.
    let repose: CGFloat

    static func of(_ season: Season, scale: CGFloat) -> SeasonStyle {
        switch season {
        case .winter:
            return SeasonStyle(
                sprites: snow(scale: scale),
                size: 3...8, fallSpeed: 35...75, sway: 18, swayRate: 0.6...1.6, spin: 0, drag: 1.6,
                rate: 55, thickness: 0.55, repose: 2.5
            )
        case .spring:
            return SeasonStyle(
                sprites: petals(scale: scale),
                size: 6...11, fallSpeed: 30...60, sway: 35, swayRate: 0.8...2, spin: 3, drag: 1.3,
                rate: 14, thickness: 0.18, repose: 3
            )
        case .summer:
            return SeasonStyle(
                sprites: sand(scale: scale),
                size: 1.5...3, fallSpeed: 110...170, sway: 6, swayRate: 1...3, spin: 0, drag: 3,
                rate: 70, thickness: 0.7, repose: 1.6
            )
        case .autumn:
            return SeasonStyle(
                sprites: leaves(scale: scale),
                size: 10...17, fallSpeed: 40...75, sway: 45, swayRate: 0.6...1.4, spin: 2.5, drag: 1.1,
                rate: 7, thickness: 0.16, repose: 3.5
            )
        }
    }

    /// Soft white dots, a little see-through.
    private static func snow(scale: CGFloat) -> [CGImage] {
        let opacities: [CGFloat] = [0.95, 0.85, 0.7]
        return opacities.map { opacity in
            sprite(side: 8, scale: scale) { context, rect in
                let colors = [NSColor.white.withAlphaComponent(opacity).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray
                let locations: [CGFloat] = [0.45, 1]
                guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: locations) else { return }
                let center = CGPoint(x: rect.midX, y: rect.midY)
                context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: rect.width / 2, options: [])
            }
        }
    }

    /// A petal: rounded at the tip, narrowing to its base, with a small notch.
    private static func petals(scale: CGFloat) -> [CGImage] {
        let colors = ["F8C8DC", "F4A7C3", "FBD9E6", "EE9AB8"]
        return colors.map { hex in
            sprite(side: 10, scale: scale) { context, rect in
                let w = rect.width
                let h = rect.height
                let path = CGMutablePath()
                path.move(to: CGPoint(x: w * 0.5, y: h * 0.05))
                path.addCurve(to: CGPoint(x: w * 0.42, y: h * 0.95), control1: CGPoint(x: w * 0.05, y: h * 0.35), control2: CGPoint(x: w * 0.1, y: h * 0.95))
                path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.86))
                path.addLine(to: CGPoint(x: w * 0.58, y: h * 0.95))
                path.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.05), control1: CGPoint(x: w * 0.9, y: h * 0.95), control2: CGPoint(x: w * 0.95, y: h * 0.35))
                context.addPath(path)
                context.setFillColor(color(hex))
                context.fillPath()
            }
        }
    }

    /// Grains in a few sand tones.
    private static func sand(scale: CGFloat) -> [CGImage] {
        let colors = ["E8D3A2", "D9BC85", "F1E2B8", "C9A66B", "B8925A"]
        return colors.map { hex in
            sprite(side: 4, scale: scale) { context, rect in
                context.setFillColor(color(hex))
                context.fillEllipse(in: rect.insetBy(dx: rect.width * 0.08, dy: rect.width * 0.08))
            }
        }
    }

    /// A leaf in autumn colours: two arcs meeting at the tip and the stem, with a vein.
    private static func leaves(scale: CGFloat) -> [CGImage] {
        let colors = ["D2691E", "B7410E", "E3A018", "8B4513", "C0392B", "DA8A2B"]
        return colors.map { hex in
            sprite(side: 16, scale: scale) { context, rect in
                let w = rect.width
                let h = rect.height
                let path = CGMutablePath()
                path.move(to: CGPoint(x: w * 0.5, y: h * 0.96))
                path.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.14), control: CGPoint(x: w * 0.02, y: h * 0.55))
                path.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.96), control: CGPoint(x: w * 0.98, y: h * 0.55))
                context.addPath(path)
                context.setFillColor(color(hex))
                context.fillPath()
                context.setStrokeColor(NSColor.black.withAlphaComponent(0.25).cgColor)
                context.setLineWidth(w * 0.05)
                context.move(to: CGPoint(x: w * 0.5, y: h * 0.02))
                context.addLine(to: CGPoint(x: w * 0.5, y: h * 0.86))
                context.strokePath()
            }
        }
    }

    private static func color(_ hex: String) -> CGColor {
        let value = UInt32(hex, radix: 16) ?? 0
        return CGColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    /// A square image `side` points wide, drawn at the screen's scale.
    private static func sprite(side: CGFloat, scale: CGFloat, draw: (CGContext, CGRect) -> Void) -> CGImage {
        let pixels = Int((side * scale).rounded(.up))
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setShouldAntialias(true)
        draw(context, CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return context.makeImage()!
    }
}
