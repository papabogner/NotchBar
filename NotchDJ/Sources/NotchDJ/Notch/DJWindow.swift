import AppKit
import Combine
import SwiftUI

/// Owns the notch window. Pointer tracking starts only when the pointer reaches the notch.
@MainActor
final class DJWindow {
    static let canvas = CGSize(width: 860, height: 640)

    let panel: NotchPanel
    private let model: DJModel
    private let sensor = PointerSensor()
    private var moveMonitors: [Any] = []
    private var clickMonitor: Any?
    private var collapseWork: DispatchWorkItem?
    private var hoverOpenWork: DispatchWorkItem?
    private var observers: Set<AnyCancellable> = []
    private var sensorUpdateQueued = false

    init(model: DJModel) {
        self.model = model
        panel = NotchPanel(contentRect: NSRect(origin: .zero, size: Self.canvas))
        let host = FirstMouseHostingView(rootView: DJRootView(model: model))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: Self.canvas)
        panel.contentView = host
        layout()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        sensor.onEnter = { [weak self] in self?.startTracking(checkNow: true) }
        Publishers.Merge(model.objectWillChange, model.now.objectWillChange)
            .sink { [weak self] _ in self?.queueSensorUpdate() }
            .store(in: &observers)
        model.$isExpanded.removeDuplicates().sink { [weak self] expanded in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.expansionChanged(expanded) } }
        }
        .store(in: &observers)
        updateSensor()
    }

    private func layout() {
        guard let screen = NotchGeometry.targetScreen() else { return }
        model.geometry = NotchGeometry.of(screen)
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
            startTracking(checkNow: false)
            if clickMonitor == nil {
                clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.model.isExpanded, !self.pointerIsInside() else { return }
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

    private func queueSensorUpdate() {
        guard !sensorUpdateQueued else { return }
        sensorUpdateQueued = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.sensorUpdateQueued = false
                self?.updateSensor()
            }
        }
    }

    private func updateSensor() {
        guard !isTracking else { sensor.hide(); return }
        sensor.cover(shapeRect())
    }

    private func shapeRect() -> NSRect {
        let size = model.size
        let frame = panel.frame
        let slack: CGFloat = model.isExpanded ? 6 : 3
        var rect = NSRect(x: frame.midX - size.width / 2 + model.shapeOffset, y: frame.maxY - size.height,
                          width: size.width, height: size.height)
            .insetBy(dx: -slack, dy: -slack)
        rect.size.height += 4
        return rect
    }

    private func pointerIsInside() -> Bool { shapeRect().contains(NSEvent.mouseLocation) }

    private func pointerMoved() {
        let inside = pointerIsInside()
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        if inside != model.isHovering {
            if inside && !model.isExpanded {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            let animation: Animation? = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? nil : .spring(response: 0.32, dampingFraction: 0.68)
            if let animation {
                withAnimation(animation) { model.isHovering = inside }
            } else {
                model.isHovering = inside
            }
        }
        if inside && !model.isExpanded && model.openOnHover {
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
        if inside {
            collapseWork?.cancel()
            collapseWork = nil
        } else if collapseWork == nil {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.collapseWork = nil
                    if !self.pointerIsInside() { self.model.close() }
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
                guard self.pointerIsInside(), !self.model.isExpanded, self.model.openOnHover else { return }
                self.model.open()
            }
        }
        hoverOpenWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}
