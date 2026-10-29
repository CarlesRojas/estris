import AppKit
import Combine
import SwiftUI

/// The Seasons utility: while on, the season's particles fall over every screen (snow in
/// winter, pink petals in spring, sand in summer, leaves in autumn) and pile up on the bottom
/// of the screen and on the top edges of windows. A window that moves or is shaken drops its
/// pile, and the pointer pushes what it passes through. Owns everything it needs, so the app
/// only has to create it and call `start()`.
@MainActor
final class Seasons {
    let settings = SeasonsSettings()
    private(set) lazy var widget = WeatherWidget(seasons: settings)
    private var scenes: [SeasonScene] = []
    private var season: Season?
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0
    private var lastPoll: CFTimeInterval = 0
    private var lastSeasonCheck: CFTimeInterval = 0
    private var pointer = NSEvent.mouseLocation
    private var pointerVelocity = CGVector.zero
    private var screensAsleep = false
    private lazy var power = PowerSource { [weak self] in self?.update() }
    private var observers: Set<AnyCancellable> = []
    private var tokens: [NSObjectProtocol] = []

    private static let frameInterval: TimeInterval = 1.0 / 60
    /// How often the windows are read again.
    private static let pollInterval: CFTimeInterval = 1.0 / 12

    func start() {
        power.start()
        widget.start()
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildScenes() }
        })
        tokens.append(center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        tokens.append(workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screensAsleep = true
                self?.update()
            }
        })
        tokens.append(workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screensAsleep = false
                self?.update()
            }
        })
        // Published values arrive before the property changes; applying on the next turn of
        // the run loop reads the new ones.
        settings.$isEnabled.map { _ in () }
            .merge(with: settings.$pausesOnBattery.map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.update() }
            .store(in: &observers)
        settings.$season
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applySeason() }
            .store(in: &observers)
        settings.$layer
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                for scene in scenes { scene.setLevel(level) }
            }
            .store(in: &observers)
    }

    /// The pane shown for this utility in Settings.
    func settingsPane() -> some View {
        SeasonsPane(settings: settings, widget: widget.settings) { [weak self] in
            self?.widget.resetPosition()
        }
    }

    private var level: NSWindow.Level {
        switch settings.layer {
        // Above other apps' windows and floating panels, below the Dock and the menu bar.
        case .inFront: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
        // Above the desktop and its icons, below every window.
        case .behind: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        }
    }

    /// Whether it should be playing now: on, the screens awake, and not paused for power.
    private var shouldRun: Bool {
        guard settings.isEnabled, !screensAsleep else { return false }
        if settings.pausesOnBattery, PowerSource.isOnBattery || ProcessInfo.processInfo.isLowPowerModeEnabled {
            return false
        }
        return true
    }

    /// Starts or stops: the scenes are made when it starts and kept while paused, so piles
    /// come back where they were.
    private func update() {
        guard settings.isEnabled else {
            stopTimer()
            for scene in scenes { scene.close() }
            scenes = []
            return
        }
        if scenes.isEmpty { rebuildScenes() }
        if shouldRun {
            for scene in scenes { scene.setHidden(false) }
            startTimer()
        } else {
            stopTimer()
            for scene in scenes { scene.setHidden(true) }
        }
    }

    private func rebuildScenes() {
        for scene in scenes { scene.close() }
        scenes = []
        guard settings.isEnabled else { return }
        let season = settings.season.season
        self.season = season
        scenes = NSScreen.screens.map { screen in
            SeasonScene(screen: screen, style: .of(season, scale: screen.backingScaleFactor), level: level)
        }
        if !shouldRun {
            for scene in scenes { scene.setHidden(true) }
        }
    }

    /// The season changed, chosen or by the date: the old one melts away.
    private func applySeason() {
        let season = settings.season.season
        guard season != self.season else { return }
        self.season = season
        let screens = NSScreen.screens
        for scene in scenes {
            let scale = screens.first { $0.frame == scene.screenFrame }?.backingScaleFactor ?? 2
            scene.setStyle(.of(season, scale: scale))
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: Self.frameInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = Self.frameInterval / 4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = CACurrentMediaTime()
        // After a stall, the world moves on by no more than a few frames.
        let dt = CGFloat(min(now - lastTick, 0.05))
        lastTick = now
        guard dt > 0 else { return }

        let location = NSEvent.mouseLocation
        let raw = CGVector(dx: (location.x - pointer.x) / dt, dy: (location.y - pointer.y) / dt)
        pointerVelocity = CGVector(dx: pointerVelocity.dx * 0.5 + raw.dx * 0.5, dy: pointerVelocity.dy * 0.5 + raw.dy * 0.5)
        pointer = location

        let windowLimit = Int(settings.windowLimit)
        let bottomLimit = Int(settings.bottomLimit)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if now - lastSeasonCheck > 60 {
            lastSeasonCheck = now
            applySeason()
        }
        if now - lastPoll >= Self.pollInterval {
            let interval = CGFloat(min(now - lastPoll, 0.5))
            lastPoll = now
            var snapshot = WindowSnapshot.read()
            if let widget = widget.collectingFrame {
                snapshot = snapshot.including(widget.frame, id: widget.id, cornerRadius: WeatherWidgetView.cornerRadius, inFront: widget.isAboveWindows)
            }
            for scene in scenes {
                scene.update(with: snapshot, interval: interval, windowLimit: windowLimit, bottomLimit: bottomLimit, hidesInFullScreen: settings.pausesInFullScreen)
            }
        }
        // Sideways air speed, in points per second. Stopped, nothing new falls; what is
        // already in the air comes down.
        let wind = CGFloat(settings.wind * SeasonsSettings.strongestWind)
        let density = settings.isFalling ? settings.density : 0
        // While a button is held (dragging a window, say), the pointer leaves the weather
        // alone: a window passing over another's pile, on its own plane, doesn't touch it.
        let isPressing = NSEvent.pressedMouseButtons != 0
        let reach = isPressing ? CGPoint(x: -100_000, y: -100_000) : pointer
        for scene in scenes {
            scene.step(dt, pointer: reach, pointerVelocity: isPressing ? .zero : pointerVelocity, density: density, wind: wind, windowLimit: windowLimit, bottomLimit: bottomLimit)
        }
        CATransaction.commit()
    }
}
