import AppKit
import Combine
import SwiftUI

/// The weather widget: a small frosted panel to start and stop the falling, and change the
/// intensity, the wind and the season. Optional, shown while Seasons is on. It sits on the
/// desktop behind windows, or above them; dragged anywhere, it stays where it is left.
@MainActor
final class WeatherWidget {
    let settings = WeatherWidgetSettings()
    private let seasons: SeasonsSettings
    private var panel: WidgetPanel?
    private var observers: Set<AnyCancellable> = []
    private var frameTokens: [NSObjectProtocol] = []
    private var screenToken: NSObjectProtocol?
    /// The room it keeps from the edges of the screen, the menu bar and the Dock.
    static let screenGap: CGFloat = 16
    /// Where its top left corner is: it stays there as controls are shown or hidden.
    private var topLeft = CGPoint.zero
    private var size = CGSize.zero

    init(seasons: SeasonsSettings) {
        self.seasons = seasons
    }

    func start() {
        // Published values arrive before the property changes; applying on the next turn of
        // the run loop reads the new ones.
        settings.$isShown.map { _ in () }
            .merge(with: settings.$placement.map { _ in () }, seasons.$isEnabled.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.update() }
            .store(in: &observers)
        // Screens added, removed or resized: it moves to the nearest place that fits.
        screenToken = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.keepOnScreen() }
        }
    }

    /// Its frame while snow and the rest may pile up on it, and whether it is above windows.
    var collectingFrame: (frame: CGRect, id: CGWindowID, isAboveWindows: Bool)? {
        guard settings.collectsWeather, let panel, panel.isVisible else { return nil }
        return (panel.frame, CGWindowID(panel.windowNumber), settings.placement == .aboveWindows)
    }

    private var level: NSWindow.Level {
        switch settings.placement {
        // Above the desktop's icons and Seasons' own layer behind windows, below every window.
        case .desktop: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 2)
        case .aboveWindows: .floating
        }
    }

    private func update() {
        guard seasons.isEnabled, settings.isShown else {
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel()
        panel.level = level
        panel.orderFrontRegardless()
    }

    private func makePanel() -> WidgetPanel {
        let panel = WidgetPanel()
        let hosting = NSHostingController(rootView: WeatherWidgetView(seasons: seasons, settings: settings))
        // The panel follows the view's size as controls are shown or hidden.
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting
        topLeft = startingTopLeft(size: panel.frame.size)
        size = panel.frame.size
        panel.setFrameTopLeftPoint(topLeft)
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            frameTokens.append(NotificationCenter.default.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.frameChanged() }
            })
        }
        self.panel = panel
        return panel
    }

    /// Dragged: remembered where it is left. Resized: kept at the same top left corner.
    /// Either way, kept clear of the screen's edges.
    private func frameChanged() {
        guard let panel else { return }
        if panel.frame.size != size {
            size = panel.frame.size
            panel.setFrameTopLeftPoint(topLeft)
            keepOnScreen()
            return
        }
        let corner = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
        guard corner != topLeft else { return }
        topLeft = corner
        settings.topLeft = corner
    }

    /// Moves it, if it has to, to the nearest place on a screen with room around it.
    private func keepOnScreen() {
        guard let panel else { return }
        let origin = Self.keptOnScreen(panel.frame)
        if origin != panel.frame.origin {
            panel.setFrameOrigin(origin)
        }
    }

    /// Where a frame goes to be on a screen, `screenGap` clear of its edges, the menu bar
    /// and the Dock: the screen under its middle, or else the nearest one.
    static func keptOnScreen(_ frame: CGRect) -> CGPoint {
        let screens = NSScreen.screens
        let middle = CGPoint(x: frame.midX, y: frame.midY)
        func distance(to rect: CGRect) -> CGFloat {
            let dx = max(rect.minX - middle.x, 0, middle.x - rect.maxX)
            let dy = max(rect.minY - middle.y, 0, middle.y - rect.maxY)
            return dx * dx + dy * dy
        }
        guard let screen = screens.first(where: { $0.frame.contains(middle) }) ?? screens.min(by: { distance(to: $0.frame) < distance(to: $1.frame) })
        else { return frame.origin }
        let area = screen.visibleFrame.insetBy(dx: screenGap, dy: screenGap)
        return CGPoint(
            x: min(max(frame.minX, area.minX), max(area.minX, area.maxX - frame.width)),
            y: min(max(frame.minY, area.minY), max(area.minY, area.maxY - frame.height))
        )
    }

    /// Where it was left, moved onto a screen if that is no longer there; at first, the top
    /// right of the main screen.
    private func startingTopLeft(size: CGSize) -> CGPoint {
        let area = NSScreen.main?.visibleFrame ?? .zero
        let corner = settings.topLeft ?? CGPoint(x: area.maxX - size.width - Self.screenGap, y: area.maxY - Self.screenGap)
        let origin = Self.keptOnScreen(CGRect(x: corner.x, y: corner.y - size.height, width: size.width, height: size.height))
        return CGPoint(x: origin.x, y: origin.y + size.height)
    }

    /// Back to the top right corner of the main screen.
    func resetPosition() {
        settings.topLeft = nil
        guard let panel else { return }
        topLeft = startingTopLeft(size: panel.frame.size)
        panel.setFrameTopLeftPoint(topLeft)
        // Its own move would remember the corner; the corner is the default, so forget it.
        settings.topLeft = nil
    }
}

/// A borderless panel that takes clicks without bringing Estris forward, on every desktop.
private final class WidgetPanel: NSPanel {
    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 240, height: 120), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
}

/// The widget's face, in the manner of a macOS desktop widget: the season large with its
/// symbol in its colour, what it is doing, and a round start/stop button; then intensity and
/// wind. Frosted glass over whatever lies behind it.
struct WeatherWidgetView: View {
    static let cornerRadius: CGFloat = 22

    @ObservedObject var seasons: SeasonsSettings
    @ObservedObject var settings: WeatherWidgetSettings

    private var season: Season { seasons.season.season }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: season.symbol)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(season.accent)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(season.title)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    if settings.showsSeason {
                        Menu {
                            Picker("Season", selection: $seasons.season) {
                                ForEach(SeasonChoice.allCases) { choice in
                                    Text(choice.title).tag(choice)
                                }
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        } label: {
                            Text(status)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.visible)
                        .fixedSize()
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    } else {
                        Text(status)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    seasons.isFalling.toggle()
                } label: {
                    Image(systemName: fallingSymbol)
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.thinMaterial))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.18)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(seasons.isFalling ? String(localized: "Stop falling") : String(localized: "Start falling"))
            }

            if settings.showsIntensity || settings.showsWind {
                VStack(spacing: 8) {
                    if settings.showsIntensity {
                        control("Intensity") {
                            Slider(value: $seasons.density, in: SeasonsSettings.densityRange)
                        } value: {
                            "\(Int((seasons.density * 100).rounded()))%"
                        }
                    }
                    if settings.showsWind {
                        control("Wind") {
                            WindSlider(value: wind, range: SeasonsSettings.windRange, fill: NSColor(season.accent))
                        } value: {
                            windText
                        }
                    }
                }
            }
        }
        .tint(season.accent)
        .padding(16)
        .frame(width: 330)
        // Dragging anywhere but its controls moves it.
        .background(WindowDragArea())
        .background(VisualEffect(cornerRadius: Self.cornerRadius))
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        )
    }

    /// A row with its name on the left, the slider, and its value on the right.
    private func control<Content: View>(_ title: LocalizedStringKey, @ViewBuilder slider: () -> Content, value: () -> String) -> some View {
        let text = value()
        return HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            slider()
                .controlSize(.small)
            Text(verbatim: text)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
    }

    /// Whether it is set to follow the date, and what the weather is doing.
    private var status: String {
        let doing = seasons.isFalling ? season.falling : String(localized: "Paused")
        return seasons.season == .automatic ? String(localized: "Automatic · \(doing)") : doing
    }

    /// Pause while falling, play while stopped.
    private var fallingSymbol: String {
        seasons.isFalling ? "pause.fill" : "play.fill"
    }

    /// Settles on calm when let go near the middle.
    private var wind: Binding<Double> {
        Binding(
            get: { seasons.wind },
            set: { seasons.wind = abs($0) < 0.06 ? 0 : $0 }
        )
    }

    private var windText: String {
        let percent = Int((abs(seasons.wind) * 100).rounded())
        guard percent > 0 else { return String(localized: "Calm") }
        return seasons.wind < 0 ? "← \(percent)%" : "\(percent)% →"
    }
}

/// The system slider for the wind, which blows either way: its bar fills from calm in the
/// middle toward the knob, with a small mark at calm, where the system's fills from the left.
struct WindSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let fill: NSColor

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider()
        slider.cell = CenteredSliderCell()
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.doubleValue = value
        slider.controlSize = .small
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.value = $value
        if slider.doubleValue != value { slider.doubleValue = value }
        if let cell = slider.cell as? CenteredSliderCell, cell.fill != fill {
            cell.fill = fill
            slider.needsDisplay = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    final class Coordinator: NSObject {
        var value: Binding<Double>

        init(value: Binding<Double>) {
            self.value = value
        }

        @objc func changed(_ slider: NSSlider) {
            value.wrappedValue = slider.doubleValue
        }
    }
}

/// A slider cell whose bar fills from the middle value, 0, to the knob.
private final class CenteredSliderCell: NSSliderCell {
    var fill: NSColor = .controlAccentColor

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let radius = rect.height / 2
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        // Where the knob's centre is at calm and now, along the stretch it travels.
        let span = maxValue - minValue
        guard span > 0 else { return }
        let travel = rect.width - knobThickness
        let start = rect.minX + knobThickness / 2
        let calm = start + travel * CGFloat((0 - minValue) / span)
        let knob = start + travel * CGFloat((doubleValue - minValue) / span)
        if abs(knob - calm) > 0.5 {
            fill.setFill()
            let filled = NSRect(x: min(calm, knob), y: rect.minY, width: abs(knob - calm), height: rect.height)
            NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
        }
        NSColor.secondaryLabelColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: calm - 0.75, y: rect.midY - rect.height * 1.25, width: 1.5, height: rect.height * 2.5), xRadius: 0.75, yRadius: 0.75).fill()
    }
}

/// Frosted glass showing what lies behind the window, blurred, rounded like a widget.
private struct VisualEffect: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        // A mask keeps the glass itself rounded: clipping the view alone leaves square
        // corners of blur.
        view.maskImage = NSImage(size: NSSize(width: cornerRadius * 2 + 1, height: cornerRadius * 2 + 1), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        view.maskImage?.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        view.maskImage?.resizingMode = .stretch
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// An area that moves its window when dragged, kept clear of the screen's edges all the way.
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragView()
    }

    func updateNSView(_ view: NSView, context: Context) {}

    private final class DragView: NSView {
        private var start: (pointer: CGPoint, origin: CGPoint)?

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            start = (NSEvent.mouseLocation, window.frame.origin)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window, let start else { return }
            let pointer = NSEvent.mouseLocation
            var frame = window.frame
            frame.origin = CGPoint(x: start.origin.x + pointer.x - start.pointer.x, y: start.origin.y + pointer.y - start.pointer.y)
            window.setFrameOrigin(WeatherWidget.keptOnScreen(frame))
        }

        override func mouseUp(with event: NSEvent) {
            start = nil
        }
    }
}
