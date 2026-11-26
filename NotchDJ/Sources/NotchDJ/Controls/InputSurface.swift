import AppKit
import SwiftUI

enum InputAxis { case vertical, horizontal, both }

/// Pointer and wheel input for knobs and faders.
///
/// AppKit reports exact drag deltas, the click count and the ⌥ key on every event, which a
/// SwiftUI gesture doesn't. Drag deltas are in points with y pointing up. Scroll deltas follow
/// the hand, not the content, so "up" means more on both a mouse and a trackpad.
/// A scroll counts as one interaction: `onBegin` on the first event, `onEnd` 0.6 s after the last.
struct InputSurface: NSViewRepresentable {
    var axis: InputAxis = .both
    var onBegin: () -> Void = {}
    var onDrag: (CGSize, Bool) -> Void
    var onEnd: () -> Void = {}
    var onDoubleClick: () -> Void = {}
    var onScroll: (CGSize, Bool) -> Void

    func makeNSView(context: Context) -> SurfaceView {
        let view = SurfaceView()
        apply(to: view)
        return view
    }

    func updateNSView(_ view: SurfaceView, context: Context) {
        apply(to: view)
    }

    private func apply(to view: SurfaceView) {
        view.axis = axis
        view.onBegin = onBegin
        view.onDrag = onDrag
        view.onEnd = onEnd
        view.onDoubleClick = onDoubleClick
        view.onScroll = onScroll
    }

    final class SurfaceView: NSView {
        var axis: InputAxis = .both
        var onBegin: (() -> Void)?
        var onDrag: ((CGSize, Bool) -> Void)?
        var onEnd: (() -> Void)?
        var onDoubleClick: (() -> Void)?
        var onScroll: ((CGSize, Bool) -> Void)?
        private var dragging = false
        private var scrolling = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            endScroll()
            if event.clickCount >= 2 {
                onDoubleClick?()
                return
            }
            dragging = true
            onBegin?()
        }

        override func mouseDragged(with event: NSEvent) {
            guard dragging else { return }
            onDrag?(CGSize(width: event.deltaX, height: -event.deltaY), event.modifierFlags.contains(.option))
        }

        override func mouseUp(with event: NSEvent) {
            guard dragging else { return }
            dragging = false
            onEnd?()
        }

        override func scrollWheel(with event: NSEvent) {
            var dx = event.scrollingDeltaX
            var dy = event.scrollingDeltaY
            if !event.hasPreciseScrollingDeltas {
                dx *= 8
                dy *= 8
            }
            if event.isDirectionInvertedFromDevice {
                dx = -dx
                dy = -dy
            }
            // Let a sideways swipe over a vertical fader scroll the strip list instead.
            if axis == .vertical && abs(dx) > abs(dy) {
                super.scrollWheel(with: event)
                return
            }
            guard dx != 0 || dy != 0, !dragging else { return }
            if !scrolling {
                scrolling = true
                onBegin?()
            }
            onScroll?(CGSize(width: dx, height: dy), event.modifierFlags.contains(.option))
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(scrollIdle), object: nil)
            perform(#selector(scrollIdle), with: nil, afterDelay: 0.6)
        }

        @objc private func scrollIdle() {
            endScroll()
        }

        private func endScroll() {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(scrollIdle), object: nil)
            guard scrolling else { return }
            scrolling = false
            onEnd?()
        }
    }
}

/// The haptic used for detents and resets.
@MainActor
enum Detent {
    static func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

/// Value readout shown above a control while it moves.
struct ValueBubble: View {
    let text: String
    @Environment(\.djTokens) private var tokens

    var body: some View {
        Text(text)
            .djFont(.value)
            .foregroundStyle(tokens.onAccent)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(tokens.accent))
            .fixedSize()
            .allowsHitTesting(false)
            .transition(.opacity)
    }
}

/// Shared detent and precision logic for knobs and faders.
///
/// The control keeps an unsnapped value while it moves, so a detent holds the output still for
/// a short stretch and then lets go, instead of trapping the pointer.
struct DetentTracker {
    var detents: [Double]
    var width: Double = 0.018
    private(set) var raw: Double?
    private var holding: Double?

    init(detents: [Double], width: Double = 0.018) {
        self.detents = detents
        self.width = width
    }

    mutating func begin(at value: Double) {
        raw = value
        holding = detents.first { abs($0 - value) < 0.0001 }
    }

    /// Moves by `delta` and returns the value to show. True in `.1` when a detent was just reached.
    mutating func move(from value: Double, by delta: Double) -> (Double, Bool) {
        let next = min(1, max(0, (raw ?? value) + delta))
        raw = next
        if let detent = detents.first(where: { abs(next - $0) < width }) {
            let entered = holding != detent
            holding = detent
            return (detent, entered)
        }
        holding = nil
        return (next, false)
    }

    mutating func end() {
        raw = nil
        holding = nil
    }
}
