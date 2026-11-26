import SwiftUI

/// A rotary control, 0...1. Drag up or right to raise it; 200 pt is the full range and ⌥ gives
/// ×0.2. The wheel works too. Double-click resets. Center and kill are detents with a haptic.
struct DJKnob: View {
    @Binding var value: Double
    var label: String
    var size: CGFloat
    var defaultValue: Double = 0.5
    /// Bipolar knobs draw their arc from the center, and stop there.
    var bipolar = true
    /// Adds a detent at 0 and shows KILL there.
    var kill = false
    var tint: Color?
    var look: KnobLook?
    var format: (Double) -> String = DJKnob.percent

    @Environment(\.djTokens) private var tokens
    @State private var tracker = DetentTracker(detents: [])
    @State private var active = false

    nonisolated static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))" }

    /// −12...+12 dB around the center, for EQ and gain knobs.
    nonisolated static func decibels(_ value: Double) -> String {
        let db = (value - 0.5) * 24
        if abs(db) < 0.25 { return "0 dB" }
        return String(format: "%+.1f dB", db)
    }

    var body: some View {
        VStack(spacing: 6) {
            KnobFace(value: value, bipolar: bipolar, look: look ?? tokens.knob, tint: tint ?? tokens.accent)
                .frame(width: size, height: size)
                .overlay {
                    InputSurface(axis: .both, onBegin: begin, onDrag: drag, onEnd: end,
                                 onDoubleClick: reset, onScroll: scroll)
                }
                .overlay(alignment: .top) {
                    if active {
                        ValueBubble(text: display(value)).offset(y: -24)
                    }
                }
            Text(label)
                .djFont(.label)
                .foregroundStyle(kill && value <= 0.02 ? tokens.accent : tokens.secondary)
                .lineLimit(1)
        }
        .animation(.easeOut(duration: 0.12), value: active)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(display(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, value + 0.05)
            case .decrement: value = max(0, value - 0.05)
            @unknown default: break
            }
        }
    }

    private var detents: [Double] {
        var list: [Double] = []
        if bipolar { list.append(0.5) }
        if kill { list.append(0) }
        return list
    }

    private func display(_ value: Double) -> String {
        if kill && value <= 0.02 { return String(localized: "KILL") }
        return format(value)
    }

    private func begin() {
        active = true
        tracker.detents = detents
        tracker.begin(at: value)
    }

    private func drag(_ delta: CGSize, _ precise: Bool) {
        apply(Double(delta.width + delta.height) / 200 * (precise ? 0.2 : 1))
    }

    private func scroll(_ delta: CGSize, _ precise: Bool) {
        apply(Double(delta.width + delta.height) / 400 * (precise ? 0.2 : 1))
    }

    private func end() {
        active = false
        tracker.end()
    }

    private func apply(_ step: Double) {
        guard step != 0 else { return }
        let (next, entered) = tracker.move(from: value, by: step)
        if entered { Detent.tick() }
        if next != value { value = next }
    }

    private func reset() {
        tracker.end()
        guard value != defaultValue else { return }
        value = defaultValue
        Detent.tick()
    }
}

/// The drawing of a knob in each template style. 0 is at seven o'clock, 1 at five o'clock.
struct KnobFace: View {
    let value: Double
    let bipolar: Bool
    let look: KnobLook
    let tint: Color

    @Environment(\.djTokens) private var tokens

    private static let sweep = 0.75
    private static let start = 135.0

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                switch look {
                case .arc: arc(side)
                case .line: line(side)
                case .ledRing: ledRing(side)
                case .solid: solid(side)
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var angle: Angle { .degrees(-135 + 270 * value) }

    private var range: (from: Double, to: Double) {
        let origin = bipolar ? 0.5 : 0
        return (min(origin, value) * Self.sweep, max(origin, value) * Self.sweep)
    }

    private func track(_ side: CGFloat, width: CGFloat, color: Color) -> some View {
        Circle()
            .trim(from: 0, to: Self.sweep)
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
            .rotationEffect(.degrees(Self.start))
            .padding(width / 2)
    }

    private func valueArc(_ side: CGFloat, width: CGFloat, color: Color) -> some View {
        Circle()
            .trim(from: range.from, to: range.to)
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
            .rotationEffect(.degrees(Self.start))
            .padding(width / 2)
    }

    private func pointer(_ side: CGFloat, width: CGFloat, length: CGFloat, inset: CGFloat, color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: length)
            .offset(y: -(side / 2 - inset - length / 2))
            .rotationEffect(angle)
    }

    private func arc(_ side: CGFloat) -> some View {
        let stroke = max(3, side * 0.075)
        return ZStack {
            track(side, width: stroke, color: tokens.raised)
            valueArc(side, width: stroke, color: tint)
            Circle()
                .fill(tokens.surface)
                .overlay(Circle().strokeBorder(tokens.line, lineWidth: 1))
                .padding(stroke + 4)
            pointer(side, width: 2, length: side * 0.2, inset: stroke + 8, color: tokens.text)
        }
    }

    private func line(_ side: CGFloat) -> some View {
        ZStack {
            Circle().strokeBorder(tokens.line, lineWidth: tokens.lineWidth).padding(side * 0.12)
            ForEach(0..<11, id: \.self) { index in
                let major = index == 0 || index == 5 || index == 10
                Rectangle()
                    .fill(major ? tokens.text : tokens.tertiary)
                    .frame(width: 1, height: major ? side * 0.09 : side * 0.05)
                    .offset(y: -side / 2 + side * 0.045)
                    .rotationEffect(.degrees(-135 + 27 * Double(index)))
            }
            pointer(side, width: 1.5, length: side * 0.3, inset: side * 0.14, color: tint)
            Circle().fill(tint).frame(width: side * 0.08, height: side * 0.08)
        }
    }

    private func ledRing(_ side: CGFloat) -> some View {
        let count = 15
        let dot = max(3, side * 0.07)
        return ZStack {
            ForEach(0..<count, id: \.self) { index in
                let t = Double(index) / Double(count - 1)
                let lit = t >= range.from / Self.sweep - 0.001 && t <= range.to / Self.sweep + 0.001
                Circle()
                    .fill(lit ? tint : tokens.meterOff)
                    .frame(width: dot, height: dot)
                    .offset(y: -side / 2 + dot / 2)
                    .rotationEffect(.degrees(-135 + 270 * t))
            }
            Circle()
                .fill(tokens.raised)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1))
                .padding(dot + 5)
            pointer(side, width: 2, length: side * 0.22, inset: dot + 9, color: .white)
        }
    }

    private func solid(_ side: CGFloat) -> some View {
        let stroke = max(4, side * 0.1)
        return ZStack {
            track(side, width: stroke, color: tokens.raised)
            valueArc(side, width: stroke, color: tint)
            Circle().fill(tint.opacity(0.14)).padding(stroke + 3)
            Circle()
                .fill(tint)
                .frame(width: side * 0.1, height: side * 0.1)
                .offset(y: -(side / 2 - stroke - side * 0.12))
                .rotationEffect(angle)
        }
    }
}
