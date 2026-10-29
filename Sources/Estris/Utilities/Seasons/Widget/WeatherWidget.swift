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
    }

    /// The pane shown for the widget in Settings.
    func settingsPane() -> some View {
        WeatherWidgetPane(settings: settings, seasons: seasons) { [weak self] in
            self?.resetPosition()
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
    private func frameChanged() {
        guard let panel else { return }
        if panel.frame.size != size {
            size = panel.frame.size
            panel.setFrameTopLeftPoint(topLeft)
            return
        }
        let corner = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
        guard corner != topLeft else { return }
        topLeft = corner
        settings.topLeft = corner
    }

    /// Where it was left, if that is still on a screen; otherwise near the top right of the
    /// main screen.
    private func startingTopLeft(size: CGSize) -> CGPoint {
        if let saved = settings.topLeft,
           NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -20, dy: -20).contains(saved) }) {
            return saved
        }
        let area = NSScreen.main?.visibleFrame ?? .zero
        return CGPoint(x: area.maxX - max(size.width, 240) - 24, y: area.maxY - 24)
    }

    private func resetPosition() {
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
            // Dragging the top row moves the widget.
            .background(WindowDragArea())

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
                            Slider(value: wind, in: SeasonsSettings.windRange)
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

/// An area that moves its window when dragged.
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragView()
    }

    func updateNSView(_ view: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
