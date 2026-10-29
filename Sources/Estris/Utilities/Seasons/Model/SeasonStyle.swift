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
    /// Whether particles stay themselves on a pile or merge into a drift.
    let pile: PileKind
    /// The steepest a pile gets: the most one column (3 points wide) stands above the next
    /// before what lands on it rolls down (about 23° for sand, which flows; snow a little
    /// steeper).
    let repose: CGFloat
    /// What a drift breaks into when dug or shaken off, when it differs from what falls.
    var debris: [SeasonStyle] = []

    /// The pieces a drift breaks into.
    var pieces: SeasonStyle {
        debris.first ?? self
    }

    static func of(_ season: Season, scale: CGFloat) -> SeasonStyle {
        switch season {
        case .winter:
            // Snow knocked off a pile falls in clumps, heavier than flakes.
            let clumps = SeasonStyle(
                sprites: clumps(scale: scale),
                size: 5...11, fallSpeed: 90...150, sway: 4, swayRate: 1...2, spin: 1.5, drag: 2.2,
                rate: 0, thickness: 0.9, pile: .snow, repose: 2.5
            )
            return SeasonStyle(
                sprites: snow(scale: scale),
                size: 2.5...6, fallSpeed: 30...65, sway: 16, swayRate: 0.6...1.6, spin: 0, drag: 1.6,
                rate: 70, thickness: 0.9, pile: .snow, repose: 2.5, debris: [clumps]
            )
        case .spring:
            return SeasonStyle(
                sprites: petals(scale: scale),
                size: 8...13, fallSpeed: 28...55, sway: 30, swayRate: 0.8...2, spin: 3, drag: 1.3,
                rate: 18, thickness: 0.22, pile: .stacked, repose: 3
            )
        case .summer:
            // Sand knocked off a pile scatters as fine grains.
            let grains = SeasonStyle(
                sprites: sand(scale: scale),
                size: 1.3...2.2, fallSpeed: 120...200, sway: 3, swayRate: 1...3, spin: 0, drag: 3.5,
                rate: 0, thickness: 0.8, pile: .sand, repose: 1.3
            )
            return SeasonStyle(
                sprites: sand(scale: scale),
                size: 2...3.5, fallSpeed: 110...170, sway: 6, swayRate: 1...3, spin: 0, drag: 3,
                rate: 80, thickness: 0.8, pile: .sand, repose: 1.3, debris: [grains]
            )
        case .autumn:
            return SeasonStyle(
                sprites: leaves(scale: scale),
                size: 8.5...13, fallSpeed: 35...65, sway: 40, swayRate: 0.6...1.4, spin: 2.5, drag: 1.1,
                rate: 9, thickness: 0.2, pile: .stacked, repose: 3.5
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

    /// Clumps of snow: a few soft balls stuck together, shaded a little underneath.
    private static func clumps(scale: CGFloat) -> [CGImage] {
        (0..<4).map { _ -> CGImage in
            let balls: [(center: CGPoint, radius: CGFloat)] = (0..<Int.random(in: 4...7)).map { _ in
                (
                    center: CGPoint(x: CGFloat.random(in: 0.3...0.7), y: CGFloat.random(in: 0.3...0.7)),
                    radius: CGFloat.random(in: 0.14...0.24)
                )
            }
            return sprite(side: 12, scale: scale) { context, rect in
                let side = rect.width
                // A cool shade below, then the bright tops.
                context.setFillColor(CGColor(srgbRed: 0.72, green: 0.78, blue: 0.88, alpha: 1))
                for ball in balls {
                    let r = ball.radius * side
                    context.fillEllipse(in: CGRect(x: ball.center.x * side - r, y: (ball.center.y - 0.03) * side - r, width: r * 2, height: r * 2))
                }
                context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
                for ball in balls {
                    let r = ball.radius * side
                    context.fillEllipse(in: CGRect(x: ball.center.x * side - r * 0.92, y: ball.center.y * side - r * 0.85, width: r * 1.84, height: r * 1.84))
                }
            }
        }
    }

    /// A cherry blossom petal: rounded at the tip, narrowing to its base, with a small notch;
    /// pale at the tip, deeper pink toward the base, with faint veins.
    private static func petals(scale: CGFloat) -> [CGImage] {
        let colors = [("FDE6EF", "F2A9C4"), ("FBD9E6", "EE9AB8"), ("FFF0F5", "F6BBD0"), ("F8C8DC", "E58AAE")]
        return colors.map { pair -> CGImage in
            let (tip, base) = pair
            return sprite(side: 16, scale: scale) { context, rect in
                let w = rect.width
                let h = rect.height
                let path = CGMutablePath()
                path.move(to: CGPoint(x: w * 0.5, y: h * 0.05))
                path.addCurve(to: CGPoint(x: w * 0.42, y: h * 0.95), control1: CGPoint(x: w * 0.05, y: h * 0.35), control2: CGPoint(x: w * 0.1, y: h * 0.95))
                path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.86))
                path.addLine(to: CGPoint(x: w * 0.58, y: h * 0.95))
                path.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.05), control1: CGPoint(x: w * 0.9, y: h * 0.95), control2: CGPoint(x: w * 0.95, y: h * 0.35))
                context.addPath(path)
                context.clip()
                let gradient = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                    colors: [color(base), color(tip)] as CFArray,
                    locations: nil
                )
                if let gradient {
                    context.drawLinearGradient(gradient, start: CGPoint(x: w * 0.5, y: h * 0.05), end: CGPoint(x: w * 0.5, y: h * 0.9), options: [])
                }
                context.setStrokeColor(color(base).copy(alpha: 0.35)!)
                context.setLineWidth(w * 0.012)
                for spread in [-0.16, -0.07, 0, 0.07, 0.16] as [CGFloat] {
                    context.move(to: CGPoint(x: w * 0.5, y: h * 0.08))
                    context.addQuadCurve(to: CGPoint(x: w * (0.5 + spread * 1.6), y: h * 0.82), control: CGPoint(x: w * (0.5 + spread * 1.2), y: h * 0.4))
                }
                context.strokePath()
            }
        }
    }

    /// Grains in a few sand tones: irregular, rounded by the sea, lit from the upper left.
    private static func sand(scale: CGFloat) -> [CGImage] {
        let colors = [("E8D3A2", "A88A58"), ("D9BC85", "8F6F42"), ("F1E2B8", "B8A074"), ("C9A66B", "7E5E34"), ("9C7A4C", "5A4428"), ("EFE6D2", "A89C84")]
        return colors.flatMap { pair -> [CGImage] in
            let (light, dark) = pair
            return (0..<2).map { _ -> CGImage in
                let corners = Int.random(in: 6...8)
                let radii = (0..<corners).map { _ in CGFloat.random(in: 0.32...0.46) }
                return sprite(side: 4, scale: scale) { context, rect in
                    let side = rect.width
                    let path = CGMutablePath()
                    for (index, radius) in radii.enumerated() {
                        let angle = CGFloat(index) / CGFloat(corners) * 2 * .pi
                        let point = CGPoint(x: side / 2 + cos(angle) * radius * side, y: side / 2 + sin(angle) * radius * side)
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    path.closeSubpath()
                    context.addPath(path)
                    context.clip()
                    let gradient = CGGradient(
                        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                        colors: [color(light), color(dark)] as CFArray,
                        locations: nil
                    )
                    if let gradient {
                        let highlight = CGPoint(x: side * 0.35, y: side * 0.65)
                        context.drawRadialGradient(gradient, startCenter: highlight, startRadius: 0, endCenter: CGPoint(x: side / 2, y: side / 2), endRadius: side * 0.5, options: [.drawsAfterEndLocation])
                    }
                }
            }
        }
    }

    /// Autumn leaves of three kinds (maple, beech and oak) in turning colours, each shaded
    /// from its middle to its edge, with a stem and veins.
    private static func leaves(scale: CGFloat) -> [CGImage] {
        // Each colour as its middle and its edge.
        let colors = [
            ("E8A33A", "B8561C"), ("D9531E", "8E2A12"), ("F0C24B", "C27A1E"),
            ("A8461E", "5E2610"), ("C9792A", "7A3C14"), ("B9A03A", "7A5A1A"),
        ]
        let shapes = [maple(), beech(), oak()]
        return shapes.flatMap { shape in
            colors.map { pair -> CGImage in
                let (middle, edge) = pair
                return sprite(side: 24, scale: scale) { context, rect in
                    let size = rect.width
                    var transform = CGAffineTransform(scaleX: size, y: size)
                    guard let outline = shape.outline.copy(using: &transform) else { return }
                    // The stem, below the blade.
                    context.setStrokeColor(color(edge))
                    context.setLineWidth(size * 0.035)
                    context.setLineCap(.round)
                    context.move(to: CGPoint(x: 0.5 * size, y: 0.02 * size))
                    context.addLine(to: CGPoint(x: 0.5 * size, y: shape.base * size))
                    context.strokePath()
                    // The blade, darker toward its edge.
                    context.saveGState()
                    context.addPath(outline)
                    context.clip()
                    let gradient = CGGradient(
                        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                        colors: [color(middle), color(edge)] as CFArray,
                        locations: nil
                    )
                    if let gradient {
                        let center = CGPoint(x: 0.5 * size, y: 0.55 * size)
                        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: 0.5 * size, options: [.drawsAfterEndLocation])
                    }
                    // Veins from the base to the tips, faint.
                    context.setStrokeColor(NSColor.black.withAlphaComponent(0.22).cgColor)
                    context.setLineWidth(size * 0.018)
                    for tip in shape.veins {
                        context.move(to: CGPoint(x: 0.5 * size, y: shape.base * size))
                        context.addLine(to: CGPoint(x: tip.x * size, y: tip.y * size))
                    }
                    context.strokePath()
                    context.restoreGState()
                    // A thin darker rim.
                    context.addPath(outline)
                    context.setStrokeColor(NSColor.black.withAlphaComponent(0.18).cgColor)
                    context.setLineWidth(size * 0.012)
                    context.strokePath()
                }
            }
        }
    }

    /// A leaf's outline in a unit square (stem at the bottom), where its blade starts, and
    /// where its main veins end.
    private struct LeafShape {
        let outline: CGPath
        let base: CGFloat
        let veins: [CGPoint]
    }

    /// Five pointed lobes.
    private static func maple() -> LeafShape {
        let points: [(CGFloat, CGFloat)] = [
            (0.50, 0.22), (0.39, 0.17), (0.40, 0.27), (0.17, 0.29), (0.24, 0.37), (0.04, 0.50),
            (0.14, 0.54), (0.10, 0.66), (0.26, 0.62), (0.28, 0.71), (0.38, 0.64), (0.35, 0.84),
            (0.44, 0.80), (0.50, 0.98), (0.56, 0.80), (0.65, 0.84), (0.62, 0.64), (0.72, 0.71),
            (0.74, 0.62), (0.90, 0.66), (0.86, 0.54), (0.96, 0.50), (0.76, 0.37), (0.83, 0.29),
            (0.60, 0.27), (0.61, 0.17),
        ]
        let path = CGMutablePath()
        path.addLines(between: points.map { CGPoint(x: $0.0, y: $0.1) })
        path.closeSubpath()
        return LeafShape(
            outline: path,
            base: 0.22,
            veins: [CGPoint(x: 0.5, y: 0.94), CGPoint(x: 0.08, y: 0.52), CGPoint(x: 0.92, y: 0.52), CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.8, y: 0.3)]
        )
    }

    /// An oval with a pointed tip and a finely toothed edge, veins in pairs off the middle.
    private static func beech() -> LeafShape {
        profileLeaf(base: 0.16, tip: 0.97, width: { t in 0.3 * pow(sin(.pi * pow(t, 0.8)), 0.9) }, teeth: 18, depth: 0.025, veinPairs: 6)
    }

    /// Rounded lobes down each side.
    private static func oak() -> LeafShape {
        profileLeaf(base: 0.16, tip: 0.96, width: { t in (0.12 + 0.2 * sin(.pi * t)) * (0.72 + 0.28 * abs(sin(t * 4.5 * .pi))) }, teeth: 0, depth: 0, veinPairs: 4)
    }

    /// A leaf traced up one side and down the other, `width(t)` being its half width at `t`
    /// (0 at the base, 1 at the tip).
    private static func profileLeaf(base: CGFloat, tip: CGFloat, width: (CGFloat) -> CGFloat, teeth: Int, depth: CGFloat, veinPairs: Int) -> LeafShape {
        let steps = 60
        func half(_ i: Int) -> (y: CGFloat, w: CGFloat) {
            let t = CGFloat(i) / CGFloat(steps)
            let tooth = teeth > 0 && i % max(1, steps / teeth) == 0 ? depth : 0
            return (base + t * (tip - base), max(0, width(t) + tooth))
        }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0.5, y: base))
        for i in 0...steps {
            let (y, w) = half(i)
            path.addLine(to: CGPoint(x: 0.5 - w, y: y))
        }
        for i in stride(from: steps, through: 0, by: -1) {
            let (y, w) = half(i)
            path.addLine(to: CGPoint(x: 0.5 + w, y: y))
        }
        path.closeSubpath()
        var veins = [CGPoint(x: 0.5, y: tip - 0.02)]
        for pair in 1...max(1, veinPairs) {
            let t = CGFloat(pair) / CGFloat(veinPairs + 1)
            let (y, w) = half(Int(t * CGFloat(steps)))
            let reach = min(1, t + 0.12)
            let y2 = base + reach * (tip - base)
            veins.append(CGPoint(x: 0.5 - w * 0.85, y: max(y, y2)))
            veins.append(CGPoint(x: 0.5 + w * 0.85, y: max(y, y2)))
        }
        return LeafShape(outline: path, base: base, veins: veins)
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
