import SwiftUI

/// A linear control, 0...1. Drags are relative, so a click never jumps the value; ⌥ gives ×0.2.
/// The wheel works too. Double-click returns to `defaultValue`, which is also a detent.
struct DJFader: View {
    @Binding var value: Double
    var label: String
    var axis: Axis = .vertical
    var defaultValue: Double = 1
    var detents: [Double] = []
    var tint: Color?
    var look: FaderLook?
    /// Peak meter drawn inside the track, for a strip.
    var meter: MeterSource?
    var format: (Double) -> String = DJKnob.percent

    @Environment(\.djTokens) private var tokens
    @State private var tracker = DetentTracker(detents: [])
    @State private var active = false

    var body: some View {
        GeometryReader { proxy in
            let length = axis == .vertical ? proxy.size.height : proxy.size.width
            FaderFace(value: value, axis: axis, look: look ?? tokens.fader, tint: tint ?? tokens.accent, meter: meter)
                .overlay {
                    InputSurface(axis: axis == .vertical ? .vertical : .horizontal,
                                 onBegin: begin,
                                 onDrag: { delta, precise in drag(delta, precise, length: length) },
                                 onEnd: end,
                                 onDoubleClick: reset,
                                 onScroll: { delta, precise in scroll(delta, precise, length: length) })
                }
                .overlay(alignment: axis == .vertical ? .top : .center) {
                    if active {
                        ValueBubble(text: format(value))
                            .offset(y: axis == .vertical ? bubbleY(length) : -proxy.size.height / 2 - 14)
                    }
                }
        }
        .animation(.easeOut(duration: 0.12), value: active)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, value + 0.04)
            case .decrement: value = max(0, value - 0.04)
            @unknown default: break
            }
        }
    }

    private func bubbleY(_ length: CGFloat) -> CGFloat {
        let travel = max(0, length - 12)
        return (1 - value) * travel - 24
    }

    private func begin() {
        active = true
        tracker.detents = allDetents
        tracker.begin(at: value)
    }

    private func drag(_ delta: CGSize, _ precise: Bool, length: CGFloat) {
        let along = axis == .vertical ? delta.height : delta.width
        apply(Double(along) / Double(max(60, length - 20)) * (precise ? 0.2 : 1))
    }

    private func scroll(_ delta: CGSize, _ precise: Bool, length: CGFloat) {
        let along = axis == .vertical ? delta.height : delta.width + delta.height
        apply(Double(along) / Double(max(120, length * 1.6)) * (precise ? 0.2 : 1))
    }

    private func end() {
        active = false
        tracker.end()
    }

    private var allDetents: [Double] {
        detents.contains(defaultValue) ? detents : detents + [defaultValue]
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

/// Which meter a fader or strip shows.
struct MeterSource {
    let bank: MeterBank
    /// Nil is the master.
    let id: String?
}

/// The drawing of a fader in each template style.
struct FaderFace: View {
    let value: Double
    let axis: Axis
    let look: FaderLook
    let tint: Color
    var meter: MeterSource?

    @Environment(\.djTokens) private var tokens

    var body: some View {
        GeometryReader { proxy in
            let vertical = axis == .vertical
            let length = vertical ? proxy.size.height : proxy.size.width
            let breadth = vertical ? proxy.size.width : proxy.size.height
            let cap = capSize(breadth: breadth)
            let travel = max(0, length - (vertical ? cap.height : cap.width))
            let position = CGFloat(value) * travel
            ZStack(alignment: vertical ? .bottom : .leading) {
                track(vertical: vertical, length: length, breadth: breadth, position: position, cap: cap)
                capView(cap)
                    .offset(x: vertical ? 0 : position, y: vertical ? -position : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: vertical ? .bottom : .leading)
            }
        }
    }

    private func capSize(breadth: CGFloat) -> CGSize {
        let vertical = axis == .vertical
        let size: CGSize
        switch look {
        case .slim: size = CGSize(width: min(breadth, 26), height: 12)
        case .line: size = CGSize(width: min(breadth, 22), height: 8)
        case .hardware: size = CGSize(width: min(breadth, 30), height: 16)
        case .thick: size = CGSize(width: min(breadth, 32), height: 6)
        }
        return vertical ? size : CGSize(width: size.height, height: size.width)
    }

    private func grooveWidth(breadth: CGFloat) -> CGFloat {
        switch look {
        case .slim: return 4
        case .line: return 1
        case .hardware: return 3
        case .thick: return min(breadth, 22)
        }
    }

    @ViewBuilder
    private func track(vertical: Bool, length: CGFloat, breadth: CGFloat, position: CGFloat, cap: CGSize) -> some View {
        let groove = grooveWidth(breadth: breadth)
        let filled = position + (vertical ? cap.height : cap.width) / 2
        ZStack(alignment: vertical ? .bottom : .leading) {
            if look == .hardware || look == .line {
                FaderScale(vertical: vertical, color: look == .line ? tokens.text : tokens.tertiary)
            }
            RoundedRectangle(cornerRadius: groove / 2, style: .continuous)
                .fill(look == .hardware ? Color.black : (look == .line ? tokens.text : tokens.raised))
                .frame(width: vertical ? groove : nil, height: vertical ? nil : groove)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if look == .slim || look == .thick {
                RoundedRectangle(cornerRadius: groove / 2, style: .continuous)
                    .fill(tint.opacity(look == .thick ? 0.85 : 1))
                    .frame(width: vertical ? groove : max(0, filled), height: vertical ? max(0, filled) : groove)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: vertical ? .bottom : .leading)
            }
            if let meter {
                MeterBar(source: meter, axis: axis, thickness: 3)
                    .frame(width: vertical ? 3 : nil, height: vertical ? nil : 3)
                    .offset(x: vertical ? groove / 2 + 5 : 0, y: vertical ? 0 : groove / 2 + 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func capView(_ cap: CGSize) -> some View {
        switch look {
        case .slim:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white)
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(tokens.line, lineWidth: 1))
                .frame(width: cap.width, height: cap.height)
        case .line:
            Rectangle()
                .fill(tint)
                .frame(width: cap.width, height: cap.height)
        case .hardware:
            ZStack {
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color(hex: 0x2B2B30))
                RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(Color.black, lineWidth: 1)
                Rectangle().fill(Color.white)
                    .frame(width: axis == .vertical ? cap.width - 8 : 1.5, height: axis == .vertical ? 1.5 : cap.height - 8)
            }
            .frame(width: cap.width, height: cap.height)
        case .thick:
            Capsule()
                .fill(tokens.text)
                .frame(width: axis == .vertical ? cap.width - 6 : cap.width,
                       height: axis == .vertical ? cap.height : cap.height - 6)
        }
    }
}

/// Tick marks beside a fader groove, every 10 %.
private struct FaderScale: View {
    let vertical: Bool
    let color: Color

    var body: some View {
        Canvas { context, size in
            let count = 11
            for index in 0..<count {
                let t = CGFloat(index) / CGFloat(count - 1)
                let major = index % 5 == 0
                let reach: CGFloat = major ? 7 : 4
                var path = Path()
                if vertical {
                    let y = size.height - 6 - t * (size.height - 12)
                    path.move(to: CGPoint(x: size.width / 2 - 6 - reach, y: y))
                    path.addLine(to: CGPoint(x: size.width / 2 - 6, y: y))
                    path.move(to: CGPoint(x: size.width / 2 + 6, y: y))
                    path.addLine(to: CGPoint(x: size.width / 2 + 6 + reach, y: y))
                } else {
                    let x = 6 + t * (size.width - 12)
                    path.move(to: CGPoint(x: x, y: size.height / 2 - 6 - reach))
                    path.addLine(to: CGPoint(x: x, y: size.height / 2 - 6))
                    path.move(to: CGPoint(x: x, y: size.height / 2 + 6))
                    path.addLine(to: CGPoint(x: x, y: size.height / 2 + 6 + reach))
                }
                context.stroke(path, with: .color(color.opacity(major ? 0.9 : 0.5)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

/// The crossfader: a long horizontal fader with a center detent and A/B legends.
struct Crossfader: View {
    @Binding var value: Double
    var height: CGFloat = 34
    var showsLegends = true

    @Environment(\.djTokens) private var tokens

    var body: some View {
        HStack(spacing: 10) {
            if showsLegends {
                Text(verbatim: "A").djFont(.label).foregroundStyle(tokens.deckA)
            }
            ZStack {
                Rectangle()
                    .fill(tokens.tertiary)
                    .frame(width: 1, height: height * 0.7)
                DJFader(value: $value, label: String(localized: "Crossfader"), axis: .horizontal,
                        defaultValue: 0.5, detents: [0.5],
                        format: { value in
                            let a = Int(((1 - value) * 100).rounded())
                            return "A \(a) · B \(100 - a)"
                        })
            }
            .frame(height: height)
            if showsLegends {
                Text(verbatim: "B").djFont(.label).foregroundStyle(tokens.deckB)
            }
        }
    }
}
