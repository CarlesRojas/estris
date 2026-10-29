import AppKit

/// How a season piles up.
enum PileKind {
    /// Each particle stays itself, lying where it landed: petals and leaves.
    case stacked
    /// Merges into soft, sticky mounds with rounded tops.
    case snow
    /// Merges into loose grains that slide down to their angle of repose.
    case sand
}

/// Draws a snow or sand drift: one shape following the drift's height in each column, left
/// out where a window in front covers it, lit from the upper left so slopes facing left catch
/// the light and those facing right fall in shade. Snow is bright and finely speckled, with a
/// cool shadow under its soft top and glints that twinkle on its surface; sand is grainy,
/// darker lower down, with a crisp sunlit edge.
@MainActor
final class DriftLayer {
    /// Tallest a drift is drawn, in points.
    static let height: CGFloat = 140

    let root = CALayer()
    private let contact = CAShapeLayer()
    private let body = CALayer()
    private let mask = CAShapeLayer()
    private let rim = CAShapeLayer()
    private let lit = CAShapeLayer()
    private let shaded = CAShapeLayer()
    private var sparkles: [Sparkle] = []
    private let kind: PileKind

    /// A glint on the snow, kept at the same place along the drift and depth under its top.
    private struct Sparkle {
        let layer: CALayer
        let along: CGFloat
        let depth: CGFloat
    }

    init(kind: PileKind, width: CGFloat, scale: CGFloat) {
        self.kind = kind
        let bounds = CGRect(x: 0, y: 0, width: width, height: Self.height)
        root.anchorPoint = .zero
        root.bounds = bounds
        // A faint shadow where the drift meets what it lies on.
        contact.frame = bounds
        contact.fillColor = NSColor.black.withAlphaComponent(0.01).cgColor
        contact.shadowColor = NSColor.black.cgColor
        contact.shadowOpacity = kind == .snow ? 0.22 : 0.3
        contact.shadowRadius = kind == .snow ? 2.5 : 1.5
        contact.shadowOffset = CGSize(width: 0, height: -1)
        root.addSublayer(contact)

        body.frame = bounds
        mask.frame = bounds
        body.mask = mask
        root.addSublayer(body)
        switch kind {
        case .snow:
            // Bluish deep down, white on top: snow in shade under a bright surface.
            let fill = CAGradientLayer()
            fill.frame = bounds
            fill.colors = [Self.color(0xB4C2D8), Self.color(0xDCE4F0), Self.color(0xF7F9FD), Self.color(0xFFFFFF)]
            fill.locations = [0, 0.05, 0.14, 1]
            fill.startPoint = CGPoint(x: 0.5, y: 0)
            fill.endPoint = CGPoint(x: 0.5, y: 1)
            body.addSublayer(fill)
            let speckles = CALayer()
            speckles.frame = bounds
            speckles.backgroundColor = NSColor(patternImage: Self.snowTexture(scale: scale)).cgColor
            body.addSublayer(speckles)
            lit.fillColor = NSColor.white.withAlphaComponent(0.35).cgColor
            shaded.fillColor = Self.color(0x6E84AC).copy(alpha: 0.16)
            // The soft top: bright, with a cool shade just under it.
            rim.strokeColor = NSColor.white.cgColor
            rim.lineWidth = 1.6
            rim.shadowColor = Self.color(0x7F93B5)
            rim.shadowOpacity = 0.55
            rim.shadowRadius = 1.6
            rim.shadowOffset = CGSize(width: 0, height: -1.4)
        case .sand, .stacked:
            let grains = CALayer()
            grains.frame = bounds
            grains.backgroundColor = NSColor(patternImage: Self.grainTexture(scale: scale)).cgColor
            body.addSublayer(grains)
            // Darker lower down, where the light doesn't reach.
            let shade = CAGradientLayer()
            shade.frame = bounds
            shade.colors = [NSColor.black.withAlphaComponent(0.22).cgColor, NSColor.black.withAlphaComponent(0).cgColor]
            shade.locations = [0, 0.12]
            shade.startPoint = CGPoint(x: 0.5, y: 0)
            shade.endPoint = CGPoint(x: 0.5, y: 1)
            body.addSublayer(shade)
            lit.fillColor = Self.color(0xFFF1CC).copy(alpha: 0.22)
            shaded.fillColor = Self.color(0x5A3D1C).copy(alpha: 0.24)
            rim.strokeColor = Self.color(0xF6E8C4)
            rim.lineWidth = 0.8
        }
        for face in [lit, shaded] {
            face.frame = bounds
            body.addSublayer(face)
        }
        rim.frame = bounds
        rim.fillColor = nil
        rim.lineJoin = .round
        root.addSublayer(rim)
        if kind == .snow {
            addSparkles(width: width, scale: scale)
        }
    }

    /// Glints scattered along the drift, each twinkling on its own beat.
    private func addSparkles(width: CGFloat, scale: CGFloat) {
        let image = Self.sparkleImage(scale: scale)
        for _ in 0..<max(1, Int(width / 14)) {
            let layer = CALayer()
            let side = CGFloat.random(in: 3...6)
            layer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            layer.contents = image
            layer.opacity = 0
            layer.isHidden = true
            let twinkle = CAKeyframeAnimation(keyPath: "opacity")
            twinkle.values = [0, 0, 1, 0, 0]
            twinkle.keyTimes = [0, 0.4, 0.5, 0.62, 1]
            twinkle.duration = .random(in: 2...6)
            twinkle.timeOffset = .random(in: 0...twinkle.duration)
            twinkle.repeatCount = .infinity
            layer.add(twinkle, forKey: "twinkle")
            root.addSublayer(layer)
            sparkles.append(Sparkle(layer: layer, along: .random(in: 0...1), depth: .random(in: 0.5...5)))
        }
    }

    /// Redraws the drift from its heights, `covered` telling which columns are hidden.
    func draw(heights: [CGFloat], columnWidth: CGFloat, covered: (Int) -> Bool) {
        let fill = CGMutablePath()
        let top = CGMutablePath()
        let litFaces = CGMutablePath()
        let shadedFaces = CGMutablePath()
        var column = 0
        while column < heights.count {
            guard !covered(column) else {
                column += 1
                continue
            }
            var end = column
            while end + 1 < heights.count, !covered(end + 1) { end += 1 }
            trace(heights, from: column, to: end, columnWidth: columnWidth, fill: fill, top: top)
            faces(heights, from: column, to: end, columnWidth: columnWidth, lit: litFaces, shaded: shadedFaces)
            column = end + 1
        }
        mask.path = fill
        contact.path = fill
        rim.path = top
        lit.path = litFaces
        shaded.path = shadedFaces
        for sparkle in sparkles {
            let column = min(heights.count - 1, Int(sparkle.along * CGFloat(heights.count)))
            let height = heights[column]
            sparkle.layer.isHidden = height < sparkle.depth + 2 || covered(column)
            sparkle.layer.position = CGPoint(x: (CGFloat(column) + 0.5) * columnWidth, y: height - sparkle.depth)
        }
    }

    /// Slopes facing the light, and those facing away, as bands under the surface that are
    /// deeper where the slope is steeper.
    private func faces(_ heights: [CGFloat], from first: Int, to last: Int, columnWidth: CGFloat, lit: CGMutablePath, shaded: CGMutablePath) {
        guard last > first else { return }
        for column in first..<last {
            let a = heights[column]
            let b = heights[column + 1]
            let slope = b - a
            guard abs(slope) > 0.15, max(a, b) > 1 else { continue }
            let depth = min(max(a, b), 3 + abs(slope) * 3)
            let x = (CGFloat(column) + 0.5) * columnWidth
            let face = CGMutablePath()
            face.move(to: CGPoint(x: x, y: a))
            face.addLine(to: CGPoint(x: x + columnWidth, y: b))
            face.addLine(to: CGPoint(x: x + columnWidth, y: max(0, b - depth)))
            face.addLine(to: CGPoint(x: x, y: max(0, a - depth)))
            face.closeSubpath()
            // Rising to the right faces left, toward the light.
            (slope > 0 ? lit : shaded).addPath(face)
        }
    }

    /// One uncovered run of columns: snow as a smooth curve through the column tops, sand as
    /// straight slopes between them.
    private func trace(_ heights: [CGFloat], from first: Int, to last: Int, columnWidth: CGFloat, fill: CGMutablePath, top: CGMutablePath) {
        let points = (first...last).map { CGPoint(x: (CGFloat($0) + 0.5) * columnWidth, y: heights[$0]) }
        let start = CGPoint(x: CGFloat(first) * columnWidth, y: heights[first])
        let end = CGPoint(x: CGFloat(last + 1) * columnWidth, y: heights[last])
        // Only what has some depth shows.
        guard points.contains(where: { $0.y > 0.3 }) else { return }
        fill.move(to: CGPoint(x: start.x, y: -1))
        fill.addLine(to: start)
        top.move(to: start)
        for path in [fill, top] {
            if kind == .snow {
                var previous = start
                for point in points {
                    path.addQuadCurve(to: CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2), control: previous)
                    previous = point
                }
                path.addQuadCurve(to: end, control: previous)
            } else {
                for point in points { path.addLine(to: point) }
                path.addLine(to: end)
            }
        }
        fill.addLine(to: CGPoint(x: end.x, y: -1))
        fill.closeSubpath()
    }

    private static func color(_ value: UInt32) -> CGColor {
        CGColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    /// Snow, close up: faint cool speckles and tiny bright crystals over the white.
    private static func snowTexture(scale: CGFloat) -> NSImage {
        tile(side: 40, scale: scale) { context, side in
            var generator = SystemRandomNumberGenerator()
            let tones: [(UInt32, ClosedRange<CGFloat>)] = [(0x9AAACC, 0.08...0.2), (0xC8D4EA, 0.15...0.35), (0xFFFFFF, 0.6...1)]
            for _ in 0..<260 {
                let tone = tones.randomElement(using: &generator)!
                let radius = CGFloat.random(in: 0.3...0.9, using: &generator)
                let x = CGFloat.random(in: 0..<side, using: &generator)
                let y = CGFloat.random(in: 0..<side, using: &generator)
                context.setFillColor(color(tone.0).copy(alpha: .random(in: tone.1, using: &generator))!)
                for dx in [-side, 0, side] {
                    for dy in [-side, 0, side] {
                        context.fillEllipse(in: CGRect(x: x + dx - radius, y: y + dy - radius, width: radius * 2, height: radius * 2))
                    }
                }
            }
        }
    }

    /// A four-pointed glint with a soft glow.
    private static func sparkleImage(scale: CGFloat) -> CGImage {
        let side: CGFloat = 8
        let pixels = Int(side * scale)
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.scaleBy(x: scale, y: scale)
        let center = CGPoint(x: side / 2, y: side / 2)
        let glow = [NSColor.white.withAlphaComponent(0.9).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray
        let locations: [CGFloat] = [0, 1]
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: glow, locations: locations) {
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: side * 0.3, options: [])
        }
        let star = CGMutablePath()
        for (dx, dy) in [(1, 0), (0, 1), (-1, 0), (0, -1)] as [(CGFloat, CGFloat)] {
            star.move(to: center)
            star.addLine(to: CGPoint(x: center.x + dx * side / 2 - dy * 0.5, y: center.y + dy * side / 2 + dx * 0.5))
            star.addLine(to: CGPoint(x: center.x + dx * side / 2 + dy * 0.5, y: center.y + dy * side / 2 - dx * 0.5))
            star.closeSubpath()
        }
        context.addPath(star)
        context.setFillColor(NSColor.white.cgColor)
        context.fillPath()
        return context.makeImage()!
    }

    /// A seamless square texture `side` points wide, drawn by `draw`.
    private static func tile(side: CGFloat, scale: CGFloat, draw: (CGContext, CGFloat) -> Void) -> NSImage {
        let pixels = Int(side * scale)
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.scaleBy(x: scale, y: scale)
        draw(context, side)
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: side, height: side))
    }

    /// Sand, close up: a warm base strewn with lighter and darker grains. Tiles seamlessly.
    private static func grainTexture(scale: CGFloat) -> NSImage {
        let side: CGFloat = 48
        let pixels = Int(side * scale)
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(color(0xDCC28E))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let tones: [UInt32] = [0xF2E2B8, 0xE8D3A2, 0xC9A66B, 0xB8925A, 0xA67C48, 0xFFF4D6, 0x8C6A3C, 0x6E5434]
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<900 {
            let radius = CGFloat.random(in: 0.3...0.85, using: &generator)
            let x = CGFloat.random(in: 0..<side, using: &generator)
            let y = CGFloat.random(in: 0..<side, using: &generator)
            context.setFillColor(color(tones.randomElement(using: &generator)!).copy(alpha: .random(in: 0.5...1, using: &generator))!)
            // Drawn again across each edge it crosses, so the tiles meet without a seam.
            for dx in [-side, 0, side] {
                for dy in [-side, 0, side] {
                    context.fillEllipse(in: CGRect(x: x + dx - radius, y: y + dy - radius, width: radius * 2, height: radius * 2))
                }
            }
        }
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: side, height: side))
    }
}
