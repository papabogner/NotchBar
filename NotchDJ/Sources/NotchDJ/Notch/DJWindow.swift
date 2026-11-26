import AppKit
import Combine
import SwiftUI

/// Owns the notch window. Pointer tracking starts only when the pointer reaches the notch.
@MainActor
final class DJWindow {
    /// Large panel plus room for the shadow.
    static let canvas = CGSize(width: 900, height: 520)

    let panel: NotchPanel
    private let model: DJModel
    private let sensor = PointerSensor()
    private var moveMonitors: [Any] = []
    private var clickMonitor: Any?
    private var collapseWork: DispatchWorkItem?
    private var hoverOpenWork: DispatchWorkItem?
    private var observers: Set<AnyCancellable> = []
    private var notificationTokens: [NSObjectProtocol] = []
    private var sensorUpdateQueued = false
    /// Opened from the keyboard or the menu bar, the panel waits for the pointer to visit
    /// before leaving it starts the close timer.
    private var pointerVisited = false

    init(model: DJModel) {
        self.model = model
        panel = NotchPanel(contentRect: NSRect(origin: .zero, size: Self.canvas))
        let root = PanelRootView(model: model, prefs: model.prefs)
            .environmentObject(model)
            .environmentObject(model.mixer)
            .environmentObject(model.now)
            .environmentObject(model.prefs)
            .environmentObject(model.permissions)
        let host = FirstMouseHostingView(rootView: root)
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: Self.canvas)
        panel.contentView = host
        layout()
        panel.orderFrontRegardless()
        applyAppearance()

        let center = NotificationCenter.default
        let window = self
        notificationTokens.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                     object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { window.layout() }
        })
        notificationTokens.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification,
                                                     object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { window.menuTracking(true) }
        })
        notificationTokens.append(center.addObserver(forName: NSMenu.didEndTrackingNotification,
                                                     object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { window.menuTracking(false) }
        })
        sensor.onEnter = { [weak self] in self?.startTracking(checkNow: true) }
        Publishers.Merge3(model.objectWillChange, model.now.objectWillChange, model.prefs.objectWillChange)
            .sink { [weak self] _ in self?.queueSensorUpdate() }
            .store(in: &observers)
        model.$isExpanded.removeDuplicates().sink { [weak self] expanded in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.expansionChanged(expanded) } }
        }
        .store(in: &observers)
        updateSensor()
    }

    /// Puts the panel under the notch of the chosen screen.
    func layout() {
        guard let screen = NotchGeometry.targetScreen() else { return }
        let geometry = NotchGeometry.of(screen)
        if geometry != model.geometry { model.geometry = geometry }
        if screen.frame.size != model.screenSize { model.screenSize = screen.frame.size }
        panel.setFrame(NSRect(x: screen.frame.midX - Self.canvas.width / 2, y: screen.frame.maxY - Self.canvas.height,
                              width: Self.canvas.width, height: Self.canvas.height), display: true)
        queueSensorUpdate()
    }

    private var isTracking: Bool { !moveMonitors.isEmpty }

    private func startTracking(checkNow: Bool) {
        guard !isTracking else { return }
        sensor.hide()
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }) { moveMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }) { moveMonitors.append(monitor) }
        if checkNow { pointerMoved() }
    }

    private func stopTracking() {
        guard isTracking else { return }
        moveMonitors.forEach(NSEvent.removeMonitor)
        moveMonitors = []
        updateSensor()
    }

    private func expansionChanged(_ expanded: Bool) {
        if expanded {
            pointerVisited = pointerIsInside()
            panel.ignoresMouseEvents = false
            startTracking(checkNow: false)
            if clickMonitor == nil {
                clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.model.isExpanded, !self.model.menuOpen, !self.pointerIsInside() else { return }
                        self.model.close()
                    }
                }
            }
        } else {
            if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
            self.clickMonitor = nil
            pointerMoved()
        }
    }

    private func menuTracking(_ open: Bool) {
        model.menuOpen = open
        if open {
            collapseWork?.cancel()
            collapseWork = nil
        } else if model.isExpanded {
            pointerMoved()
        }
    }

    private func applyAppearance() {
        let name: NSAppearance.Name = model.prefs.isDark ? .darkAqua : .aqua
        if panel.appearance?.name != name { panel.appearance = NSAppearance(named: name) }
    }

    private func queueSensorUpdate() {
        guard !sensorUpdateQueued else { return }
        sensorUpdateQueued = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sensorUpdateQueued = false
                self.applyAppearance()
                self.updateSensor()
            }
        }
    }

    private func updateSensor() {
        guard !isTracking else { sensor.hide(); return }
        if model.hidesPill && !model.isExpanded {
            sensor.hide()
            return
        }
        sensor.cover(shapeRect())
    }

    private func shapeRect() -> NSRect {
        let size = model.size
        let frame = panel.frame
        let slack: CGFloat = model.isExpanded ? 6 : 3
        var rect = NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height,
                          width: size.width, height: size.height)
            .insetBy(dx: -slack, dy: -slack)
        rect.size.height += 4
        return rect
    }

    private func pointerIsInside() -> Bool { shapeRect().contains(NSEvent.mouseLocation) }

    private func pointerMoved() {
        let inside = pointerIsInside() && !(model.hidesPill && !model.isExpanded)
        let ignores = !(inside || model.menuOpen)
        if panel.ignoresMouseEvents != ignores { panel.ignoresMouseEvents = ignores }
        if inside != model.isHovering && !model.isExpanded {
            if inside { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
            if let animation = Motion.hover {
                withAnimation(animation) { model.isHovering = inside }
            } else {
                model.isHovering = inside
            }
        } else if model.isExpanded && model.isHovering {
            model.isHovering = false
        }
        if inside && !model.isExpanded && model.prefs.openOnHover {
            scheduleHoverOpen()
        } else {
            hoverOpenWork?.cancel()
            hoverOpenWork = nil
        }
        guard model.isExpanded else {
            collapseWork?.cancel()
            collapseWork = nil
            if !inside { stopTracking() }
            return
        }
        if inside { pointerVisited = true }
        if inside || model.menuOpen || !pointerVisited {
            collapseWork?.cancel()
            collapseWork = nil
        } else if collapseWork == nil {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.collapseWork = nil
                    if !self.pointerIsInside() && !self.model.menuOpen { self.model.close() }
                }
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    private func scheduleHoverOpen() {
        guard hoverOpenWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.hoverOpenWork = nil
                guard self.pointerIsInside(), !self.model.isExpanded, self.model.prefs.openOnHover else { return }
                self.model.open()
            }
        }
        hoverOpenWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}
