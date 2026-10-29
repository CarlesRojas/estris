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

/// Draws a snow or sand drift as a picture rendered pixel by pixel from its heights, left out
/// where a window in front covers it. Each point is lit from the upper left by the slope of
/// the drift there, darker where the drift meets what it lies on, over a texture kept fixed
/// to the screen so it doesn't shimmer as the drift grows: sand as grains of a few tones with
/// dark and bright specks, snow as a fine, faintly blue grain with a soft, uneven top and
/// glints that flash on its surface.
@MainActor
final class DriftLayer {
    /// Tallest a drift is drawn, in points.
    static let height: CGFloat = 140
    /// Drawn again at most this often, in seconds.
    private static let drawInterval: CFTimeInterval = 1.0 / 20

    let root = CALayer()
    private let picture = CALayer()
    private let kind: PileKind
    private let scale: CGFloat
    private let width: CGFloat
    private let pixelWidth: Int
    /// Where the drift starts on the screen, in pixels, so its texture stays put.
    private let noiseOrigin: Int32
    /// The texture's value at each pixel, rows from the bottom, made as tall as needed.
    private var texture: [Float] = []
    private var textureRows = 0
    private var sparkles: [Sparkle] = []
    private var lastDraw: CFTimeInterval = 0

    /// A glint on the snow, kept at the same place along the drift and depth under its top.
    private struct Sparkle {
        let layer: CALayer
        let along: CGFloat
        let depth: CGFloat
    }

    init(kind: PileKind, width: CGFloat, scale: CGFloat, screenX: CGFloat) {
        self.kind = kind
        self.scale = scale
        self.width = width
        pixelWidth = max(1, Int((width * scale).rounded(.up)))
        noiseOrigin = Int32(truncatingIfNeeded: Int((screenX * scale).rounded()))
        root.anchorPoint = .zero
        root.bounds = CGRect(x: 0, y: 0, width: width, height: Self.height)
        picture.anchorPoint = .zero
        picture.position = .zero
        picture.magnificationFilter = .nearest
        root.addSublayer(picture)
        if kind == .snow {
            addSparkles()
        }
    }

    /// Whether it has been long enough since the last drawing to draw again.
    var canDraw: Bool {
        CACurrentMediaTime() - lastDraw >= Self.drawInterval
    }

    /// Draws the drift from its heights, `covered` telling which columns are hidden.
    func draw(heights: [CGFloat], columnWidth: CGFloat, covered: (Int) -> Bool) {
        lastDraw = CACurrentMediaTime()
        let count = heights.count
        let deepest = heights.max() ?? 0
        guard deepest > 0.15, count > 0 else {
            picture.contents = nil
            for sparkle in sparkles { sparkle.layer.isHidden = true }
            return
        }
        let rows = min(Int(Self.height * scale), Int(((deepest + 2) * scale).rounded(.up)))
        makeTexture(rows: rows)
        var pixels = [UInt32](repeating: 0, count: pixelWidth * rows)
        let pixelScale = Float(scale)
        // Light from the upper left.
        let lightX: Float = -0.55
        let lightY: Float = 0.835
        for x in 0..<pixelWidth {
            let point = (CGFloat(x) + 0.5) / scale
            let column = min(count - 1, Int(point / columnWidth))
            guard !covered(column) else { continue }
            // The surface between column centres, and its slope there, measured across a
            // column either side so it changes smoothly.
            let surface = Self.surface(heights, at: point, columnWidth: columnWidth)
            guard surface > 0.05 else { continue }
            let slope = (Self.surface(heights, at: point + columnWidth, columnWidth: columnWidth)
                - Self.surface(heights, at: point - columnWidth, columnWidth: columnWidth)) / Float(2 * columnWidth)
            // How squarely the surface faces the light: 1 where flat.
            let surfaceFacing = max(0, (-slope * lightX + lightY) / (slope * slope + 1).squareRoot()) / lightY
            let top = surface * pixelScale
            for row in 0...min(rows - 1, Int(top)) {
                var coverage = min(1, top - Float(row))
                guard coverage > 0 else { continue }
                let height = (Float(row) + 0.5) / pixelScale
                let depth = surface - height
                let grain = texture[row * pixelWidth + x]
                // The slope's light shows near the surface and fades deeper in.
                let facing = 1 + (surfaceFacing - 1) * exp(-depth / 4)
                // Shadow where it meets what it lies on.
                let contact = 1 - 0.26 * exp(-height / 2.5)
                var red: Float
                var green: Float
                var blue: Float
                switch kind {
                case .snow:
                    var light = (0.3 + 0.7 * min(1.05, facing)) * contact
                    // A little bluer deeper in, where less light reaches.
                    light *= 1 - 0.14 * min(1, depth / 30)
                    light *= 1 + (grain - 0.5) * 0.09
                    red = 0.66 + (0.98 - 0.66) * light
                    green = 0.73 + (0.985 - 0.73) * light
                    blue = 0.86 + (1 - 0.86) * light
                    // A soft, uneven top, as fresh snow has.
                    if depth < 1 { coverage *= 0.6 + 0.4 * grain }
                case .sand, .stacked:
                    red = 0.66 + 0.27 * grain
                    green = 0.51 + 0.29 * grain
                    blue = 0.32 + 0.28 * grain
                    var light = (0.42 + 0.62 * facing) * contact
                    // The crest catches the light.
                    if depth < 0.6 { light *= 1.07 }
                    red *= light
                    green *= light
                    blue *= light
                }
                pixels[(rows - 1 - row) * pixelWidth + x] = Self.pack(red, green, blue, coverage)
            }
        }
        let data = pixels.withUnsafeBytes { Data($0) } as CFData
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(
                  width: pixelWidth, height: rows, bitsPerComponent: 8, bitsPerPixel: 32,
                  bytesPerRow: pixelWidth * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              )
        else { return }
        picture.bounds = CGRect(x: 0, y: 0, width: CGFloat(pixelWidth) / scale, height: CGFloat(rows) / scale)
        picture.contents = image

        for sparkle in sparkles {
            let column = min(count - 1, Int(sparkle.along * CGFloat(count)))
            let height = heights[column]
            sparkle.layer.isHidden = height < sparkle.depth + 1.5 || covered(column)
            sparkle.layer.position = CGPoint(x: (CGFloat(column) + 0.5) * columnWidth, y: height - sparkle.depth)
        }
    }

    /// The drift's height at a point along it, between column centres.
    private static func surface(_ heights: [CGFloat], at point: CGFloat, columnWidth: CGFloat) -> Float {
        let position = point / columnWidth - 0.5
        let left = max(0, min(heights.count - 1, Int(position.rounded(.down))))
        let right = min(heights.count - 1, left + 1)
        let fraction = Float(max(0, min(1, position - position.rounded(.down))))
        return Float(heights[left]) + Float(heights[right] - heights[left]) * fraction
    }

    /// The texture, made at least `rows` tall.
    private func makeTexture(rows: Int) {
        guard rows > textureRows else { return }
        let made = min(Int(Self.height * scale), max(rows, textureRows * 2, 32))
        // About a point per grain, whatever the screen's scale.
        let cell = Int32(max(1, scale.rounded()))
        var values = [Float](repeating: 0, count: pixelWidth * made)
        for row in 0..<made {
            let y = Int32(row)
            for column in 0..<pixelWidth {
                let x = noiseOrigin &+ Int32(column)
                let value: Float
                switch kind {
                case .snow:
                    value = 0.5 * Self.hash(x, y) + 0.5 * Self.smoothNoise(x, y, cell: 6 * cell)
                case .sand, .stacked:
                    let grain = Self.hash(x / cell, y / cell)
                    var tone = 0.45 * grain + 0.2 * Self.hash(x, y) + 0.35 * Self.smoothNoise(x, y, cell: 12 * cell)
                    // Now and then a dark mineral grain or a bright one of quartz.
                    let speck = Self.hash(x / cell &+ 7919, y / cell &+ 104_729)
                    if speck < 0.04 {
                        tone *= 0.4
                    } else if speck > 0.97 {
                        tone = min(1, tone + 0.35)
                    }
                    value = tone
                }
                values[row * pixelWidth + column] = value
            }
        }
        texture = values
        textureRows = made
    }

    /// Glints scattered along the drift, each flashing briefly on its own beat.
    private func addSparkles() {
        let image = Self.glint(scale: scale)
        for _ in 0..<max(1, Int(width / 10)) {
            let layer = CALayer()
            let side = CGFloat.random(in: 3...6)
            layer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            layer.contents = image
            layer.opacity = 0
            layer.isHidden = true
            let flash = CAKeyframeAnimation(keyPath: "opacity")
            flash.values = [0, 0, 1, 0, 0]
            flash.keyTimes = [0, 0.45, 0.5, 0.56, 1]
            flash.duration = .random(in: 1.2...4.5)
            flash.timeOffset = .random(in: 0...flash.duration)
            flash.repeatCount = .infinity
            layer.add(flash, forKey: "flash")
            root.addSublayer(layer)
            sparkles.append(Sparkle(layer: layer, along: .random(in: 0...1), depth: .random(in: 0.3...3)))
        }
    }

    /// A tiny point of light with a faint glow and short, thin rays.
    private static func glint(scale: CGFloat) -> CGImage {
        let side: CGFloat = 6
        let pixels = Int(side * scale)
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.scaleBy(x: scale, y: scale)
        let center = CGPoint(x: side / 2, y: side / 2)
        let glow = [NSColor.white.cgColor, NSColor.white.withAlphaComponent(0.35).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray
        let locations: [CGFloat] = [0, 0.2, 1]
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: glow, locations: locations) {
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: side * 0.42, options: [])
        }
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(0.35)
        context.move(to: CGPoint(x: 0.5, y: center.y))
        context.addLine(to: CGPoint(x: side - 0.5, y: center.y))
        context.move(to: CGPoint(x: center.x, y: 0.5))
        context.addLine(to: CGPoint(x: center.x, y: side - 0.5))
        context.strokePath()
        return context.makeImage()!
    }

    /// A pixel, premultiplied, its bytes in RGBA order.
    private static func pack(_ red: Float, _ green: Float, _ blue: Float, _ alpha: Float) -> UInt32 {
        let alpha = max(0, min(1, alpha))
        let r = UInt32(max(0, min(1, red)) * alpha * 255)
        let g = UInt32(max(0, min(1, green)) * alpha * 255)
        let b = UInt32(max(0, min(1, blue)) * alpha * 255)
        return r | g << 8 | b << 16 | UInt32(alpha * 255) << 24
    }

    /// A random value from 0 to 1, always the same for the same point.
    private static func hash(_ x: Int32, _ y: Int32) -> Float {
        var value = UInt32(bitPattern: x) &* 374_761_393 &+ UInt32(bitPattern: y) &* 668_265_263
        value = (value ^ (value >> 13)) &* 1_274_126_177
        value ^= value >> 16
        return Float(value) / Float(UInt32.max)
    }

    /// Random values blended smoothly between points `cell` pixels apart.
    private static func smoothNoise(_ x: Int32, _ y: Int32, cell: Int32) -> Float {
        let cellX = x >= 0 ? x / cell : (x - cell + 1) / cell
        let cellY = y / cell
        let fx = Float(x - cellX * cell) / Float(cell)
        let fy = Float(y - cellY * cell) / Float(cell)
        let sx = fx * fx * (3 - 2 * fx)
        let sy = fy * fy * (3 - 2 * fy)
        let a = hash(cellX, cellY)
        let b = hash(cellX + 1, cellY)
        let c = hash(cellX, cellY + 1)
        let d = hash(cellX + 1, cellY + 1)
        return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy
    }
}
