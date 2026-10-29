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

/// The widget's face: the season and a start/stop button on top, then intensity and wind.
struct WeatherWidgetView: View {
    @ObservedObject var seasons: SeasonsSettings
    @ObservedObject var settings: WeatherWidgetSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: seasons.season.season.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 22)
                if settings.showsSeason {
                    Picker("Season", selection: $seasons.season) {
                        ForEach(SeasonChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                } else {
                    Text(seasons.season.season.title)
                        .font(.headline)
                }
                Spacer(minLength: 4)
                Button {
                    seasons.isFalling.toggle()
                } label: {
                    Image(systemName: fallingSymbol)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.primary.opacity(0.12)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(seasons.isFalling ? String(localized: "Stop falling") : String(localized: "Start falling"))
            }
            // Dragging the top row moves the widget.
            .background(WindowDragArea())

            if settings.showsIntensity {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Intensity")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $seasons.density, in: SeasonsSettings.densityRange) {
                        Text("Intensity")
                    } minimumValueLabel: {
                        Image(systemName: "aqi.low")
                    } maximumValueLabel: {
                        Image(systemName: "aqi.high")
                    }
                    .labelsHidden()
                }
            }
            if settings.showsWind {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Wind")
                        Spacer()
                        Text(windText)
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Slider(value: wind, in: SeasonsSettings.windRange) {
                        Text("Wind")
                    } minimumValueLabel: {
                        Image(systemName: "arrow.left")
                    } maximumValueLabel: {
                        Image(systemName: "arrow.right")
                    }
                    .labelsHidden()
                }
            }
        }
        .padding(14)
        .frame(width: 240)
        .background(VisualEffect())
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
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

/// The frosted background of a HUD.
private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
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
