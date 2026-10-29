import AppKit

/// One falling or resting particle: a flake, a petal, a grain or a leaf.
final class Particle {
    enum State {
        case falling
        case resting
        /// Fading away: melted off a full pile, or landed where nothing may stay.
        case melting
    }

    let layer = CALayer()
    var position: CGPoint
    var velocity: CGVector
    var angle: CGFloat
    var spin: CGFloat
    /// Leaves and petals tumble as they fall: how far turned edge-on, and how fast.
    let tumbles: Bool
    var flip: CGFloat
    let flipRate: CGFloat
    let size: CGFloat
    let fallSpeed: CGFloat
    let swayRate: CGFloat
    let phase: CGFloat
    /// How much it adds to a pile.
    let thickness: CGFloat
    var state = State.falling
    var meltLeft: CGFloat = 0
    /// The pile it rests on, and in which column.
    weak var surface: Surface?
    var column = 0
    var isGone = false

    init(position: CGPoint, style: SeasonStyle) {
        let size = CGFloat.random(in: style.size)
        let fallSpeed = CGFloat.random(in: style.fallSpeed)
        self.position = position
        self.size = size
        self.fallSpeed = fallSpeed
        swayRate = CGFloat.random(in: style.swayRate)
        phase = CGFloat.random(in: 0...(2 * .pi))
        thickness = size * style.thickness
        velocity = CGVector(dx: 0, dy: -fallSpeed)
        angle = style.spin > 0 ? CGFloat.random(in: 0...(2 * .pi)) : 0
        spin = style.spin > 0 ? CGFloat.random(in: -style.spin...style.spin) : 0
        tumbles = style.pile == .stacked
        flip = CGFloat.random(in: 0...(2 * .pi))
        let flipDirection: CGFloat = Bool.random() ? 1 : -1
        flipRate = CGFloat.random(in: 1.5...4) * flipDirection
        layer.contents = style.sprites.randomElement()
        layer.contentsGravity = .resizeAspect
        layer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
    }

    /// Moves its layer to where it is, `origin` being the screen's bottom left corner.
    func place(from origin: CGPoint) {
        layer.position = CGPoint(x: position.x - origin.x, y: position.y - origin.y)
        if tumbles {
            // Turning edge-on and back: foreshortened across, never quite to a line.
            let facing = max(0.15, abs(cos(flip)))
            layer.setAffineTransform(CGAffineTransform(rotationAngle: angle).scaledBy(x: facing, y: 1))
        } else if angle != 0 {
            layer.setAffineTransform(CGAffineTransform(rotationAngle: angle))
        }
    }
}

/// Where particles pile up: the bottom of a screen or the top edge of a window. Split into
/// narrow columns, so a pile has a shape. Petals and leaves stay themselves, each column a
/// stack of them, and what lands on a column standing well above its neighbour rolls down to
/// it. Snow and sand become a drift instead: each column only a depth, the grains merged,
/// settling every frame to the slope the material holds.
@MainActor
final class Surface {
    static let columnWidth: CGFloat = 3

    let isFloor: Bool
    let kind: PileKind
    /// How a drift is drawn; none for stacked piles.
    var drift: DriftLayer?
    /// A drift still moving toward its slope, or needing to be drawn again.
    private(set) var isSettling = false
    var needsDraw = false
    /// Drift that slid off each end, or was dug out, not yet turned back into grains.
    var spilledLeft: CGFloat = 0
    var spilledRight: CGFloat = 0
    var dug: CGFloat = 0
    /// Drift the wind lifted into the air, not yet turned into flying grains or flakes.
    var blown: CGFloat = 0
    /// When, in the scene's time, it starts collecting: a window that just moved collects
    /// nothing until it has been still a moment, so a dragged or shaken window stays clear.
    var collectsFrom: CGFloat = 0
    /// A window's drift that holds all it may: what falls on it carries on past.
    var isFull = false
    private(set) var minX: CGFloat
    private(set) var y: CGFloat
    private(set) var columns: [[Particle]]
    private(set) var heights: [CGFloat]
    /// What it lies on, below its top edge, in each column: 0 along a flat edge, dropping
    /// down a window's rounded corners, so what lands there slides off as it would.
    let base: [CGFloat]
    /// The most a drift's column holds where it lies on a slope: nothing on the steep end of
    /// a rounded corner, where it slides off; no limit where it lies flat.
    let capacity: [CGFloat]
    /// Resting particles, oldest first: the first to melt once the pile is full.
    private(set) var settled: [Particle] = []
    /// Parts hidden by windows in front, as ranges of x: nothing lands or shows there.
    var occluders: [Occluder] = []

    init(minX: CGFloat, maxX: CGFloat, y: CGFloat, isFloor: Bool, kind: PileKind, leftRadius: CGFloat = 0, rightRadius: CGFloat = 0) {
        self.minX = minX
        self.y = y
        self.isFloor = isFloor
        self.kind = kind
        let count = max(1, Int((maxX - minX) / Self.columnWidth))
        columns = Array(repeating: [], count: count)
        heights = Array(repeating: 0, count: count)
        let width = CGFloat(count) * Self.columnWidth
        base = (0..<count).map { column in
            let x = (CGFloat(column) + 0.5) * Self.columnWidth
            return min(Self.corner(radius: leftRadius, at: x), Self.corner(radius: rightRadius, at: width - x))
        }
        // The slope of the edge itself across each column, from the curve: steepest at the
        // very end of a corner, where the column next to it alone wouldn't tell.
        func profile(_ x: CGFloat) -> CGFloat {
            let x = max(0, min(width, x))
            return min(Self.corner(radius: leftRadius, at: x), Self.corner(radius: rightRadius, at: width - x))
        }
        capacity = (0..<count).map { column in
            let x = (CGFloat(column) + 0.5) * Self.columnWidth
            let slope = abs(profile(x + 0.5) - profile(x - 0.5))
            return Self.capacity(on: slope, kind: kind)
        }
    }

    /// How deep a drift stays on a slope: sand slides off past about 30°, snow clings a
    /// little more, to about 50°.
    private static func capacity(on slope: CGFloat, kind: PileKind) -> CGFloat {
        let (holds, bare): (CGFloat, CGFloat) = kind == .snow ? (0.7, 1.2) : (0.4, 0.6)
        if slope <= holds { return .greatestFiniteMagnitude }
        if slope >= bare { return 0 }
        let cling: CGFloat = kind == .snow ? 3 : 1.5
        return cling * (bare - slope) / (bare - holds)
    }

    /// How far a rounded corner of `radius` drops below the top edge, `distance` in from the
    /// side.
    private static func corner(radius: CGFloat, at distance: CGFloat) -> CGFloat {
        guard radius > 0, distance < radius else { return 0 }
        let across = radius - distance
        return -(radius - (radius * radius - across * across).squareRoot())
    }

    /// Where the pile's top is in a column, from its top edge: what it lies on and its depth.
    func elevation(_ column: Int) -> CGFloat {
        base[column] + heights[column]
    }

    var maxX: CGFloat { minX + CGFloat(columns.count) * Self.columnWidth }

    func column(at x: CGFloat) -> Int? {
        guard x >= minX, x < maxX else { return nil }
        return min(columns.count - 1, Int((x - minX) / Self.columnWidth))
    }

    func isCovered(_ point: CGPoint) -> Bool {
        occluders.contains { $0.contains(point) }
    }

    /// The pile's top in a column.
    func top(_ column: Int) -> CGFloat {
        y + elevation(column)
    }

    func add(_ particle: Particle, at column: Int) {
        particle.position = CGPoint(
            x: minX + (CGFloat(column) + 0.5) * Self.columnWidth + .random(in: -1...1),
            y: top(column) + particle.thickness / 2
        )
        heights[column] += particle.thickness
        columns[column].append(particle)
        settled.append(particle)
        particle.surface = self
        particle.column = column
        particle.state = .resting
        particle.velocity = .zero
        if particle.tumbles {
            // Lying down: on its side, seen a little from above.
            let side: CGFloat = Bool.random() ? .pi / 2 : -.pi / 2
            particle.angle = side + CGFloat.random(in: -0.45...0.45)
            particle.flip = CGFloat.random(in: 0...0.9)
        }
    }

    /// Takes a particle out of the pile; those above it sink into its place.
    func remove(_ particle: Particle, origin: CGPoint) {
        let column = particle.column
        if let index = columns[column].firstIndex(where: { $0 === particle }) {
            columns[column].remove(at: index)
            for above in columns[column][index...] {
                above.position.y -= particle.thickness
                above.place(from: origin)
            }
            heights[column] = max(0, heights[column] - particle.thickness)
        }
        settled.removeAll { $0 === particle }
        particle.surface = nil
    }

    /// All the drift there is, in points of depth summed over its columns.
    var volume: CGFloat {
        heights.reduce(0, +)
    }

    /// Adds to a drift, spread over the column where it lands and its neighbours: snow wider,
    /// as it settles softly.
    func deposit(_ amount: CGFloat, at column: Int) {
        let ceiling = DriftLayer.height - 10
        let spread: [(Int, CGFloat)] = kind == .snow
            ? [(-2, 0.1), (-1, 0.2), (0, 0.4), (1, 0.2), (2, 0.1)]
            : [(-1, 0.25), (0, 0.5), (1, 0.25)]
        for (offset, share) in spread {
            let target = min(columns.count - 1, max(0, column + offset))
            heights[target] = min(ceiling, heights[target] + amount * share)
        }
        isSettling = true
        needsDraw = true
    }

    /// Takes depth out of a drift's column, as the pointer digs through it.
    func dig(_ amount: CGFloat, at column: Int) {
        heights[column] = max(0, heights[column] - amount)
        dug += amount
        isFull = false
        isSettling = true
        needsDraw = true
    }

    /// Lowers a whole drift evenly to hold no more than `volume`, as snow settles.
    func shrink(to volume: CGFloat) {
        let total = self.volume
        guard total > volume, total > 0 else { return }
        let factor = volume / total
        heights = heights.map { $0 * factor }
        needsDraw = true
    }

    /// One step of a drift settling: where two neighbouring columns' tops differ by more
    /// than `repose`, some of the higher slides onto the lower, down a rounded corner too.
    /// Sand slides freely and pours off a window's edge; snow sticks, holds steeper sides,
    /// clings a little over the edge and smooths into soft mounds. The screen's edges are
    /// walls.
    func settle(repose: CGFloat) {
        guard isSettling else { return }
        let count = heights.count
        let sticky = kind == .snow
        let rate: CGFloat = sticky ? 0.2 : 0.4
        var moved: CGFloat = 0
        // Beyond the ends: a wall at the screen's edges; off a window's side, a drop that
        // snow clings to a little.
        func outside(_ column: Int) -> CGFloat {
            isFloor ? elevation(column) : base[column] + (sticky ? heights[column] * 0.55 : 0)
        }
        // Alternating sweeps, so nothing drifts one way.
        let forward = Bool.random()
        for step in 0...count {
            let left = forward ? step - 1 : count - 1 - step
            let right = left + 1
            let a = left >= 0 ? elevation(left) : outside(0)
            let b = right < count ? elevation(right) : outside(count - 1)
            let difference = a - b
            guard abs(difference) > repose else { continue }
            // No more than the higher column holds: a bare slope has nothing to slide.
            let giver = difference > 0 ? left : right
            guard giver >= 0, giver < count else { continue }
            let amount = min(heights[giver], (abs(difference) - repose) * rate)
            guard amount > 0 else { continue }
            if difference > 0 {
                heights[left] -= amount
                if right < count { heights[right] += amount } else { spilledRight += amount }
            } else {
                guard right < count else { continue }
                heights[right] -= amount
                if left >= 0 { heights[left] += amount } else { spilledLeft += amount }
            }
            moved += amount
        }
        // Evens out, keeping all it has, until the surface is smooth: snow into soft
        // curves with no peaks, sand easing into any hollow beside it.
        // Each pair of neighbours trades a share of their difference, so nothing is made or
        // lost, at the ends too.
        var smoothed: CGFloat = 0
        if count > 1 {
            let smoothing: CGFloat = sticky ? 0.12 : 0.05
            let before = (0..<count).map(elevation)
            for column in 0..<(count - 1) {
                var flow = smoothing * (before[column] - before[column + 1])
                flow = flow > 0 ? min(flow, heights[column]) : max(flow, -heights[column + 1])
                heights[column] -= flow
                heights[column + 1] += flow
                smoothed = max(smoothed, abs(flow))
            }
        }
        // What a corner can't hold slides outward, and off the side.
        for column in 0..<count where heights[column] > capacity[column] {
            let excess = heights[column] - capacity[column]
            heights[column] = capacity[column]
            let outward = column < count / 2 ? column - 1 : column + 1
            if outward < 0 {
                spilledLeft += excess
            } else if outward >= count {
                spilledRight += excess
            } else {
                heights[outward] += excess
            }
            moved += excess
        }
        if moved > 0 || smoothed > 0.002 { needsDraw = true }
        if moved < 0.01, smoothed < 0.002 { isSettling = false }
    }

    /// The wind carries the top of a drift along, once it blows harder than a light breeze:
    /// the loose top few points of each column move downwind, some of it lifted into the
    /// air. Off a window's downwind end it blows away; at the screen's edge it drifts up
    /// against it. `wind` is a share of the strongest, negative to the left.
    func blow(_ wind: CGFloat, dt: CGFloat) {
        let calm: CGFloat = kind == .snow ? 0.15 : 0.2
        let strength = abs(wind) - calm
        let count = heights.count
        guard strength > 0, count > 1 else { return }
        let step = wind > 0 ? 1 : -1
        let rate = min(0.5, strength * (kind == .snow ? 1.5 : 2.5) * dt)
        // Downwind first, so each bit moves one column a step.
        let order: [Int] = step > 0 ? Array((0..<count).reversed()) : Array(0..<count)
        var moved: CGFloat = 0
        for column in order {
            let carried = min(heights[column], 3) * rate
            guard carried > 0.0001 else { continue }
            heights[column] -= carried
            let lifted = carried * 0.25
            blown += lifted
            let next = column + step
            if next >= 0, next < count {
                heights[next] += carried - lifted
            } else if isFloor {
                heights[column] += carried - lifted
            } else if step < 0 {
                spilledLeft += carried - lifted
            } else {
                spilledRight += carried - lifted
            }
            moved += carried
        }
        if moved > 0 {
            isSettling = true
            needsDraw = true
        }
    }

    /// Lets go of every particle, which fall from where they are.
    func releaseAll(velocity: CGVector) -> [Particle] {
        let released = settled
        for particle in released {
            particle.surface = nil
            particle.state = .falling
            particle.velocity = CGVector(
                dx: velocity.dx + .random(in: -25...25),
                dy: velocity.dy + .random(in: 0...40)
            )
        }
        settled = []
        columns = columns.map { _ in [] }
        heights = heights.map { _ in 0 }
        return released
    }
}

/// The effect on one screen: a click-through window holding a layer per particle, and the
/// piles on the screen's bottom and on the top edges of windows.
@MainActor
final class SeasonScene {
    let screenFrame: CGRect
    private let visibleFrame: CGRect
    private let window: OverlayWindow
    private var style: SeasonStyle
    private let scale: CGFloat
    private var particles: [Particle] = []
    private var floor: Surface
    private var tops: [CGWindowID: Surface] = [:]
    private var spawnDebt = 0.0
    private var time: CGFloat = 0
    /// Hidden while a full screen app shows on it.
    private(set) var isHidden = false

    /// How far the pointer reaches, in points.
    private static let pointerReach: CGFloat = 70
    private static let meltTime: CGFloat = 1.5

    init(screen: NSScreen, style: SeasonStyle, level: NSWindow.Level) {
        screenFrame = screen.frame
        visibleFrame = screen.visibleFrame
        self.style = style
        scale = screen.backingScaleFactor
        window = OverlayWindow(frame: screen.frame)
        window.level = level
        // The very bottom of the screen; in front of windows, the Dock hides what lies behind it.
        floor = Surface(minX: screenFrame.minX, maxX: screenFrame.maxX, y: screenFrame.minY, isFloor: true, kind: style.pile)
        attachDrift(to: floor)
        window.orderFrontRegardless()
    }

    var origin: CGPoint { screenFrame.origin }

    private var rootLayer: CALayer? { window.contentView?.layer }

    /// How much one particle adds to a drift, on average.
    private var unit: CGFloat {
        (style.size.lowerBound + style.size.upperBound) / 2 * style.thickness
    }

    /// How much of a drift one piece thrown out of it carries: a clump of snow carries a
    /// lot, a grain of sand very little, so a drift breaks into a few clumps or many grains.
    private var pieceUnit: CGFloat {
        let pieces = style.pieces
        return (pieces.size.lowerBound + pieces.size.upperBound) / 2 * pieces.thickness
    }

    /// A pile for the current season; a drift is drawn under everything falling.
    private func makeSurface(minX: CGFloat, maxX: CGFloat, y: CGFloat, isFloor: Bool, quietFor: CGFloat = 0, leftRadius: CGFloat = 0, rightRadius: CGFloat = 0) -> Surface {
        let surface = Surface(minX: minX, maxX: maxX, y: y, isFloor: isFloor, kind: style.pile, leftRadius: leftRadius, rightRadius: rightRadius)
        surface.collectsFrom = time + quietFor
        attachDrift(to: surface)
        return surface
    }

    private func attachDrift(to surface: Surface) {
        guard surface.kind != .stacked else { return }
        let drift = DriftLayer(kind: surface.kind, width: surface.maxX - surface.minX, scale: scale, screenX: surface.minX - origin.x)
        drift.root.position = CGPoint(x: surface.minX - origin.x, y: surface.y - origin.y)
        rootLayer?.insertSublayer(drift.root, at: 0)
        surface.drift = drift
    }

    private func discard(_ surface: Surface) {
        surface.drift?.root.removeFromSuperlayer()
        surface.drift = nil
    }

    func close() {
        window.close()
    }

    func setLevel(_ level: NSWindow.Level) {
        window.level = level
    }

    func setHidden(_ hidden: Bool) {
        guard hidden != isHidden else { return }
        isHidden = hidden
        if hidden {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    /// Another season: what is there melts away and the new one starts falling.
    func setStyle(_ style: SeasonStyle) {
        for surface in [floor] + Array(tops.values) {
            for particle in surface.settled {
                surface.remove(particle, origin: origin)
                melt(particle)
            }
            discard(surface)
        }
        for particle in particles where particle.state == .falling {
            melt(particle)
        }
        self.style = style
        floor = makeSurface(minX: screenFrame.minX, maxX: screenFrame.maxX, y: screenFrame.minY, isFloor: true)
        // Window tops start again on the next look at the windows.
        tops = [:]
    }

    /// Follows the windows: piles on windows that moved or closed fall, new top edges start
    /// collecting, and parts hidden by windows in front are left alone.
    func update(with snapshot: WindowSnapshot, interval: CGFloat, windowLimit: Int, bottomLimit: Int, hidesInFullScreen: Bool) {
        setHidden(hidesInFullScreen && snapshot.hasFullScreenWindow(on: screenFrame))
        var seen = Set<CGWindowID>()
        for (index, info) in snapshot.windows.enumerated() {
            let top = info.frame.maxY
            let minX = max(info.frame.minX, screenFrame.minX)
            let maxX = min(info.frame.maxX, screenFrame.maxX)
            // Its top edge on this screen, below the menu bar, which would hide its pile.
            guard top > visibleFrame.minY, top < visibleFrame.maxY - 4, maxX - minX >= 20 else { continue }
            seen.insert(info.id)
            // Its corners are rounded where its side is on this screen.
            let leftRadius = info.frame.minX >= screenFrame.minX ? info.cornerRadius : 0
            let rightRadius = info.frame.maxX <= screenFrame.maxX ? info.cornerRadius : 0
            if let surface = tops[info.id] {
                if abs(surface.y - top) > 0.5 || abs(surface.minX - minX) > 0.5 || abs(surface.maxX - maxX) > Surface.columnWidth {
                    // Moved or resized: its pile falls, flung along when it was shaken.
                    let velocity = CGVector(
                        dx: max(-1500, min(1500, (minX - surface.minX) / interval)),
                        dy: max(-1500, min(1500, (top - surface.y) / interval))
                    )
                    scatter(surface, velocity: velocity)
                    tops[info.id] = makeSurface(minX: minX, maxX: maxX, y: top, isFloor: false, quietFor: 0.3, leftRadius: leftRadius, rightRadius: rightRadius)
                }
            } else {
                tops[info.id] = makeSurface(minX: minX, maxX: maxX, y: top, isFloor: false, leftRadius: leftRadius, rightRadius: rightRadius)
            }
            if let surface = tops[info.id] {
                let occluders = snapshot.occluders(ofTopOf: index)
                if occluders != surface.occluders { surface.needsDraw = true }
                surface.occluders = occluders
                for particle in surface.settled {
                    particle.layer.isHidden = surface.isCovered(particle.position)
                }
                trim(surface, to: windowLimit)
            }
        }
        // Closed, minimized or on another Space: its pile falls.
        for (id, surface) in tops where !seen.contains(id) {
            scatter(surface, velocity: .zero)
            tops[id] = nil
        }
        trim(floor, to: bottomLimit)
    }

    /// Moves everything on by `dt` seconds.
    func step(_ dt: CGFloat, pointer: CGPoint, pointerVelocity: CGVector, density: Double, wind: CGFloat, windowLimit: Int, bottomLimit: Int) {
        guard !isHidden else { return }
        time += dt
        // With wind, particles start upwind beyond the screen's edge, so it fills evenly,
        // and may drift that far out before they are gone.
        let meanFall = (style.fallSpeed.lowerBound + style.fallSpeed.upperBound) / 2
        let margin = 40 + abs(wind) * screenFrame.height / meanFall
        spawn(dt, density: density, wind: wind, margin: margin)

        let reach = Self.pointerReach
        let pull = min(1, 6 * dt)
        let drag = min(1, style.drag * dt)
        let surfaces = windowLimit > 0 ? [floor] + Array(tops.values) : [floor]
        for particle in particles {
            switch particle.state {
            case .resting:
                continue
            case .melting:
                particle.meltLeft -= dt
                particle.layer.opacity = Float(max(0, particle.meltLeft / Self.meltTime))
                if particle.meltLeft <= 0 { particle.isGone = true }
                continue
            case .falling:
                break
            }
            // The air: falling at its own speed, swaying, carried by the wind.
            let sway = style.sway * sin(time * particle.swayRate + particle.phase)
            particle.velocity.dx += (wind + sway - particle.velocity.dx) * drag
            particle.velocity.dy += (-particle.fallSpeed - particle.velocity.dy) * drag
            // The pointer pushes what it passes through and carries it along.
            let dx = particle.position.x - pointer.x
            let dy = particle.position.y - pointer.y
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance < reach {
                let force = 1 - distance / reach
                let away = 300 * force * dt / max(distance, 1)
                particle.velocity.dx += pointerVelocity.dx * force * pull + dx * away
                particle.velocity.dy += pointerVelocity.dy * force * pull + dy * away
                if style.spin > 0 {
                    particle.spin += pointerVelocity.dx * force * 0.004
                }
            }
            particle.spin *= 1 - min(1, 0.5 * dt)
            particle.angle += particle.spin * dt
            if particle.tumbles {
                // Faster through the air it moves through, as a leaf catches it.
                let speed = (particle.velocity.dx * particle.velocity.dx + particle.velocity.dy * particle.velocity.dy).squareRoot()
                particle.flip += particle.flipRate * dt * (0.6 + speed / 150)
            }

            let previous = particle.position
            particle.position.x += particle.velocity.dx * dt
            particle.position.y += particle.velocity.dy * dt
            land(particle, from: previous, on: surfaces, windowLimit: windowLimit, bottomLimit: bottomLimit)

            if particle.state == .falling,
               particle.position.x < screenFrame.minX - margin || particle.position.x > screenFrame.maxX + margin
                || particle.position.y < screenFrame.minY - 40 {
                particle.isGone = true
            }
            particle.place(from: origin)
        }
        kickPiles(near: pointer, velocity: pointerVelocity)
        let windShare = wind / CGFloat(SeasonsSettings.strongestWind)
        settleDrifts(dt: dt, wind: wind, windShare: windShare)
        blowStacks(dt: dt, wind: wind, windShare: windShare)

        if particles.contains(where: \.isGone) {
            for particle in particles where particle.isGone {
                if let surface = particle.surface { surface.remove(particle, origin: origin) }
                particle.layer.removeFromSuperlayer()
            }
            particles.removeAll(where: \.isGone)
        }
    }

    private func spawn(_ dt: CGFloat, density: Double, wind: CGFloat, margin: CGFloat) {
        // Wider with wind, to cover where particles start upwind.
        let span = screenFrame.width + (wind == 0 ? 0 : margin)
        spawnDebt += style.rate * density * Double(span / 1440) * Double(dt)
        let cap = Int(500 * density)
        var falling = particles.reduce(0) { $0 + ($1.state == .falling ? 1 : 0) }
        while spawnDebt >= 1 {
            spawnDebt -= 1
            guard falling < cap else { continue }
            let start = CGPoint(
                x: .random(in: (screenFrame.minX - (wind > 0 ? margin : 30))...(screenFrame.maxX + (wind < 0 ? margin : 30))),
                y: screenFrame.maxY + style.size.upperBound
            )
            let particle = Particle(position: start, style: style)
            particle.place(from: origin)
            rootLayer?.addSublayer(particle.layer)
            particles.append(particle)
            falling += 1
        }
    }

    /// Lands a particle that crossed the top of a pile on its way down.
    private func land(_ particle: Particle, from previous: CGPoint, on surfaces: [Surface], windowLimit: Int, bottomLimit: Int) {
        guard particle.velocity.dy < 0 else { return }
        var best: (surface: Surface, column: Int, top: CGFloat)?
        for surface in surfaces where surface.collectsFrom <= time && !surface.isFull {
            guard let column = surface.column(at: particle.position.x) else { continue }
            let top = surface.top(column)
            guard previous.y >= top - 0.5, particle.position.y < top,
                  !surface.isCovered(CGPoint(x: particle.position.x, y: top)),
                  top > (best?.top ?? -.infinity)
            else { continue }
            best = (surface, column, top)
        }
        guard let best else { return }
        let surface = best.surface
        let landing = best.column
        let limit = surface.isFloor ? bottomLimit : windowLimit
        guard limit > 0 else {
            // Nothing may stay: it lands and melts.
            particle.position.y = surface.top(landing) + particle.thickness / 2
            melt(particle)
            return
        }
        if surface.kind != .stacked {
            // Snow and sand join the drift and are no longer particles of their own.
            surface.deposit(particle.thickness, at: landing)
            if surface.isFloor {
                // The bottom of the screen settles lower as it fills.
                surface.shrink(to: CGFloat(limit) * unit)
            } else {
                surface.isFull = surface.volume >= CGFloat(limit) * unit
            }
            particle.isGone = true
            return
        }

        // Lands a column either side of where it hit, so piles fill out evenly, then rolls
        // down while its column stands too far above a neighbour. Past a window's edge, it
        // falls off.
        var column = min(surface.columns.count - 1, max(0, landing + Int.random(in: -1...1)))
        for _ in 0..<60 {
            let height = surface.elevation(column)
            let edge: CGFloat = surface.isFloor ? height : surface.base[column] - 1
            let left = column > 0 ? surface.elevation(column - 1) : edge
            let right = column < surface.columns.count - 1 ? surface.elevation(column + 1) : edge
            guard height - min(left, right) > style.repose else { break }
            let step = left < right ? -1 : right < left ? 1 : Bool.random() ? -1 : 1
            let next = column + step
            if next < 0 || next >= surface.columns.count {
                particle.position = CGPoint(x: step < 0 ? surface.minX - 2 : surface.maxX + 2, y: surface.y + height)
                particle.velocity = CGVector(dx: CGFloat(step) * 30, dy: 0)
                return
            }
            column = next
        }
        if surface.settled.count >= limit, let oldest = surface.settled.first {
            surface.remove(oldest, origin: origin)
            melt(oldest)
        }
        surface.add(particle, at: column)
        particle.spin = 0
        particle.layer.isHidden = surface.isCovered(particle.position)
    }

    /// A quick pointer sweeping through a pile scatters it.
    private func kickPiles(near pointer: CGPoint, velocity: CGVector) {
        let speed = (velocity.dx * velocity.dx + velocity.dy * velocity.dy).squareRoot()
        // Sand gives way to a slow hand; snow and leaves need a quick sweep.
        guard speed > (style.pile == .sand ? 60 : 150) else { return }
        let reach = Self.pointerReach * 0.6
        for surface in [floor] + Array(tops.values) {
            guard pointer.y > surface.y - reach, pointer.x > surface.minX - reach, pointer.x < surface.maxX + reach,
                  let first = surface.column(at: max(surface.minX, pointer.x - reach)),
                  let last = surface.column(at: min(surface.maxX - 0.01, pointer.x + reach))
            else { continue }
            if surface.kind != .stacked {
                dig(surface, columns: first...last, pointer: pointer, velocity: velocity, speed: speed, reach: reach)
                continue
            }
            for column in first...last {
                for particle in surface.columns[column] {
                    let dx = particle.position.x - pointer.x
                    let dy = particle.position.y - pointer.y
                    let distance = (dx * dx + dy * dy).squareRoot()
                    guard distance < reach, !particle.layer.isHidden else { continue }
                    let force = 1 - distance / reach
                    surface.remove(particle, origin: origin)
                    particle.state = .falling
                    particle.velocity = CGVector(
                        dx: velocity.dx * 0.5 * force + .random(in: -30...30),
                        dy: abs(velocity.dy) * 0.3 * force + speed * 0.15 * force + .random(in: 20...60)
                    )
                    if style.spin > 0 { particle.spin = .random(in: -style.spin...style.spin) * 2 }
                }
            }
        }
    }

    /// The pointer digs through a drift, throwing up clumps of snow or a spray of sand.
    private func dig(_ surface: Surface, columns: ClosedRange<Int>, pointer: CGPoint, velocity: CGVector, speed: CGFloat, reach: CGFloat) {
        for column in columns {
            let x = surface.minX + (CGFloat(column) + 0.5) * Surface.columnWidth
            let top = surface.top(column)
            let dx = x - pointer.x
            let dy = top - pointer.y
            let distance = (dx * dx + dy * dy).squareRoot()
            guard distance < reach, surface.heights[column] > 0, !surface.isCovered(CGPoint(x: x, y: top)) else { continue }
            let force = 1 - distance / reach
            surface.dig(min(surface.heights[column], force * 6 * min(1.5, speed / 400)), at: column)
            var thrown = 0
            while surface.dug >= pieceUnit, thrown < (surface.kind == .sand ? 12 : 3) {
                surface.dug -= pieceUnit
                thrown += 1
                emit(
                    at: CGPoint(x: x, y: surface.top(column) + 1),
                    velocity: CGVector(
                        dx: velocity.dx * 0.5 * force + .random(in: -40...40),
                        dy: abs(velocity.dy) * 0.3 * force + speed * 0.15 * force + .random(in: 20...70)
                    )
                )
            }
        }
        // What can't be thrown this frame is lost in the spray.
        surface.dug = min(surface.dug, pieceUnit * 4)
    }

    /// Lets each drift settle toward its slope, turns what slid off a window's edge into
    /// falling grains, and draws what changed.
    private func settleDrifts(dt: CGFloat, wind: CGFloat, windShare: CGFloat) {
        for surface in [floor] + Array(tops.values) where surface.kind != .stacked {
            surface.blow(windShare, dt: dt)
            for _ in 0..<(surface.kind == .sand ? 3 : 1) {
                surface.settle(repose: style.repose)
            }
            // What the wind lifts flies off: fine snow as flakes, sand as grains.
            let lifted = surface.kind == .snow ? style : style.pieces
            let liftedUnit = (lifted.size.lowerBound + lifted.size.upperBound) / 2 * lifted.thickness
            var flying = 0
            while surface.blown >= liftedUnit, flying < 10 {
                surface.blown -= liftedUnit
                flying += 1
                let column = Int.random(in: 0..<surface.heights.count)
                let x = surface.minX + (CGFloat(column) + 0.5) * Surface.columnWidth
                guard surface.heights[column] > 0.5, !surface.isCovered(CGPoint(x: x, y: surface.top(column))) else { continue }
                emit(
                    at: CGPoint(x: x, y: surface.top(column) + 0.5),
                    velocity: CGVector(dx: wind * .random(in: 0.6...1.1), dy: .random(in: 10...45)),
                    style: lifted
                )
            }
            surface.blown = min(surface.blown, liftedUnit * 4)
            while surface.spilledLeft >= pieceUnit {
                surface.spilledLeft -= pieceUnit
                emit(at: CGPoint(x: surface.minX - 1, y: surface.top(0)), velocity: CGVector(dx: -CGFloat.random(in: 8...30), dy: 0))
            }
            while surface.spilledRight >= pieceUnit {
                surface.spilledRight -= pieceUnit
                emit(at: CGPoint(x: surface.maxX + 1, y: surface.top(surface.heights.count - 1)), velocity: CGVector(dx: CGFloat.random(in: 8...30), dy: 0))
            }
            if surface.needsDraw, let drift = surface.drift, drift.canDraw {
                surface.needsDraw = false
                let corner = CGPoint(x: surface.minX, y: surface.y)
                let occluders = surface.occluders
                drift.draw(heights: surface.heights, base: surface.base, columnWidth: Surface.columnWidth, hasOccluders: !occluders.isEmpty) { x, y in
                    let point = CGPoint(x: corner.x + x, y: corner.y + y)
                    return occluders.contains { $0.contains(point) }
                }
            }
        }
    }

    /// A pile whose window moved, closed or went away: a stacked one lets its particles fall;
    /// a drift breaks up into grains or clumps, flung along with the window.
    private func scatter(_ surface: Surface, velocity: CGVector) {
        defer { discard(surface) }
        guard surface.kind != .stacked else {
            fall(surface.releaseAll(velocity: velocity))
            return
        }
        let deepest = surface.heights.max() ?? 0
        guard deepest > 0 else { return }
        let count = min(surface.kind == .sand ? 900 : 160, Int(surface.volume / pieceUnit))
        for _ in 0..<count {
            // Mostly from where the drift is deep.
            var column = Int.random(in: 0..<surface.heights.count)
            for _ in 0..<8 where surface.heights[column] < CGFloat.random(in: 0...deepest) {
                column = Int.random(in: 0..<surface.heights.count)
            }
            let x = surface.minX + (CGFloat(column) + 0.5) * Surface.columnWidth
            guard !surface.isCovered(CGPoint(x: x, y: surface.top(column))) else { continue }
            emit(
                at: CGPoint(x: x, y: surface.y + surface.base[column] + CGFloat.random(in: 0...max(0.1, surface.heights[column]))),
                velocity: CGVector(dx: velocity.dx + .random(in: -25...25), dy: velocity.dy + .random(in: 0...40))
            )
        }
    }

    /// Strong wind picks the top leaves and petals off their piles and blows them away.
    private func blowStacks(dt: CGFloat, wind: CGFloat, windShare: CGFloat) {
        guard style.pile == .stacked else { return }
        let chance = (abs(windShare) - 0.25) * 0.8 * dt
        guard chance > 0 else { return }
        for surface in [floor] + Array(tops.values) {
            for column in 0..<surface.columns.count {
                guard let top = surface.columns[column].last, !top.layer.isHidden, CGFloat.random(in: 0...1) < chance else { continue }
                surface.remove(top, origin: origin)
                top.state = .falling
                top.velocity = CGVector(dx: wind * .random(in: 0.5...0.9), dy: .random(in: 30...90))
                top.spin = .random(in: -style.spin...style.spin) * 2
            }
        }
    }

    /// A new falling piece of a drift: a clump of snow or a grain of sand, or what the
    /// wind lifts.
    private func emit(at point: CGPoint, velocity: CGVector, style: SeasonStyle? = nil) {
        let particle = Particle(position: point, style: style ?? self.style.pieces)
        particle.velocity = velocity
        particle.place(from: origin)
        rootLayer?.addSublayer(particle.layer)
        particles.append(particle)
    }

    /// Melts the oldest of a pile until it holds no more than `limit`.
    private func trim(_ surface: Surface, to limit: Int) {
        if surface.kind != .stacked {
            surface.shrink(to: CGFloat(limit) * unit)
            surface.isFull = !surface.isFloor && surface.volume >= CGFloat(limit) * unit * 0.98
            return
        }
        while surface.settled.count > limit, let oldest = surface.settled.first {
            surface.remove(oldest, origin: origin)
            melt(oldest)
        }
    }

    private func fall(_ released: [Particle]) {
        for particle in released where style.spin > 0 {
            particle.spin = .random(in: -style.spin...style.spin)
        }
    }

    private func melt(_ particle: Particle) {
        particle.state = .melting
        particle.meltLeft = Self.meltTime
        particle.velocity = .zero
    }
}

/// A click-through window over a whole screen, for the particles' layers.
private final class OverlayWindow: NSWindow {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let view = NSView()
        view.wantsLayer = true
        contentView = view
        setFrame(frame, display: false)
    }

    /// Kept exactly over the screen: macOS would push a window off the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
