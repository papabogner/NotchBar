import AppKit
import Combine
import SwiftUI

/// Owns the notch window, keeps it over the notch, and decides when it reacts to the pointer.
///
/// The window is always the full canvas size, but it lets clicks pass through everywhere
/// except the visible black shape.
///
/// Pointer tracking only runs while it's needed. When the notch is closed and the pointer is
/// elsewhere, a `PointerSensor` over the notch waits for the pointer to arrive, so ordinary
/// mouse use never wakes NotchBar. Once the pointer is on the notch, or the notch is open,
/// NotchBar follows each move until the pointer leaves the closed notch again.
@MainActor
final class NotchController {
    static let canvas = CGSize(width: 800, height: 560)

    let panel: NotchPanel
    private let vm: NotchViewModel
    private let sensor = PointerSensor()
    private var moveMonitors: [Any] = []
    private var clickMonitor: Any?
    private var collapseWork: DispatchWorkItem?
    private var hoverOpenWork: DispatchWorkItem?
    private var observers: Set<AnyCancellable> = []
    private var sensorUpdateQueued = false

    init(vm: NotchViewModel) {
        self.vm = vm
        panel = NotchPanel(contentRect: NSRect(origin: .zero, size: Self.canvas))
        let host = FirstMouseHostingView(rootView: NotchRootView(vm: vm, media: vm.media, usage: vm.usage, timer: vm.timer))
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
        // Anything that changes the notch's size or position moves the sensor with it.
        Publishers.MergeMany(vm.objectWillChange, vm.media.objectWillChange, vm.timer.objectWillChange, vm.dictation.objectWillChange)
            .sink { [weak self] _ in self?.queueSensorUpdate() }
            .store(in: &observers)
        vm.$isExpanded.removeDuplicates().sink { [weak self] expanded in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.expansionChanged(expanded) } }
        }
        .store(in: &observers)
        Publishers.CombineLatest4(vm.$showsSpotify, vm.$showsMini, vm.$showsTickerSettings, vm.$showsAppearance)
            .map { $0 || $1 || $2 || $3 }
            .removeDuplicates()
            .sink { [weak self] typing in
                MainActor.assumeIsolated { self?.setTyping(typing) }
            }
            .store(in: &observers)
        vm.$hideFromScreenshots.removeDuplicates().sink { [weak self] hidden in
            guard let self else { return }
            // Windows that aren't shared are left out of screen capture by every screenshot
            // and recording tool, including the system's.
            self.panel.sharingType = hidden ? .none : .readOnly
            self.sensor.setHiddenFromCapture(hidden)
        }
        .store(in: &observers)
        updateSensor()
    }

    private func layout() {
        guard let screen = NotchGeometry.targetScreen() else { return }
        vm.geometry = NotchGeometry.of(screen)
        panel.setFrame(NSRect(x: screen.frame.midX - Self.canvas.width / 2, y: screen.frame.maxY - Self.canvas.height,
                              width: Self.canvas.width, height: Self.canvas.height), display: true)
        queueSensorUpdate()
    }

    // MARK: Pointer

    private var isTracking: Bool { !moveMonitors.isEmpty }

    /// For the debug state.
    var debugPointer: String { "tracking=\(isTracking) sensor[\(sensor.debugSummary)] shape=\(NSStringFromRect(shapeRect())) ignores=\(panel.ignoresMouseEvents)" }

    /// Follows every pointer move, while the pointer is on the notch or the notch is open.
    /// `checkNow` reacts to where the pointer is at once, for when it just arrived.
    private func startTracking(checkNow: Bool) {
        guard !isTracking else { return }
        sensor.hide()
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }) { moveMonitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }) { moveMonitors.append(m) }
        if checkNow { pointerMoved() }
    }

    /// Hands watching back to the sensor once the pointer has left the closed notch.
    private func stopTracking() {
        guard isTracking else { return }
        moveMonitors.forEach(NSEvent.removeMonitor)
        moveMonitors = []
        updateSensor()
    }

    private func expansionChanged(_ expanded: Bool) {
        if expanded {
            // Opened from the keyboard, the pointer may be anywhere: wait until it moves.
            startTracking(checkNow: false)
            // A click anywhere else closes the open notch, like the Dynamic Island.
            if clickMonitor == nil {
                clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.vm.isExpanded, !self.vm.acceptsText, !self.pointerIsInside() else { return }
                        self.vm.close()
                    }
                }
            }
        } else {
            if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
            clickMonitor = nil
            pointerMoved()
        }
    }

    /// Size changes come in bursts, so the sensor moves once, after they settle.
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

    /// The visible shape in screen coordinates, with a little slack around it.
    private func shapeRect() -> NSRect {
        let size = vm.size
        let frame = panel.frame
        let slack: CGFloat = vm.isExpanded ? 6 : 3
        var rect = NSRect(x: frame.midX - size.width / 2 + vm.shapeOffset, y: frame.maxY - size.height, width: size.width, height: size.height)
            .insetBy(dx: -slack, dy: -slack)
        rect.size.height += 4  // the very top row of pixels counts as inside
        return rect
    }

    private func pointerIsInside() -> Bool { shapeRect().contains(NSEvent.mouseLocation) }

    /// Runs for every pointer move anywhere, so it does as little as possible.
    private func pointerMoved() {
        let inside = pointerIsInside()
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        if inside != vm.isHovering {
            if inside && !vm.isExpanded {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.68)) { vm.isHovering = inside }
        }
        if inside && !vm.isExpanded && vm.openOnHover {
            scheduleHoverOpen()
        } else {
            hoverOpenWork?.cancel()
            hoverOpenWork = nil
        }
        guard vm.isExpanded else {
            collapseWork?.cancel()
            collapseWork = nil
            if !inside { stopTracking() }
            return
        }
        if inside {
            vm.isSticky = false
            collapseWork?.cancel()
            collapseWork = nil
        } else if vm.acceptsText {
            collapseWork?.cancel()
            collapseWork = nil
        } else if collapseWork == nil && !vm.isSticky {
            // Close shortly after the pointer leaves, unless it comes back.
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.collapseWork = nil
                    if !self.pointerIsInside() && !self.vm.isMenuOpen && !self.vm.acceptsText { self.vm.close() }
                }
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    /// Opens after a pause so a pointer that only crosses the notch does not pop it open.
    /// A click still opens immediately; if the notch is already open this does nothing.
    private func scheduleHoverOpen() {
        guard hoverOpenWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.hoverOpenWork = nil
                guard self.pointerIsInside(), !self.vm.isExpanded, self.vm.openOnHover else { return }
                let tab: NotchViewModel.Tab = (self.vm.mixerOnHover && self.vm.isEnabled(.mixer)) ? .mixer : self.vm.preferredTab
                self.vm.open(tab)
            }
        }
        hoverOpenWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func showSettings() { SettingsWindow.show(vm: vm) }

    /// The panel stays out of the way until a text field is on screen.
    private func setTyping(_ on: Bool) {
        panel.allowsTyping = on
        guard on else {
            if panel.isKeyWindow { panel.resignKey() }
            return
        }
        collapseWork?.cancel()
        collapseWork = nil
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
