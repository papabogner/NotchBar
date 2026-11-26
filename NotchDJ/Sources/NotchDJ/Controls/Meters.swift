import SwiftUI

private struct MetersLiveKey: EnvironmentKey {
    static var defaultValue: Bool { true }
}

extension EnvironmentValues {
    /// False when no readings can arrive (meters off, or no capture access). Meters then stop redrawing.
    var metersLive: Bool {
        get { self[MetersLiveKey.self] }
        set { self[MetersLiveKey.self] = newValue }
    }
}

/// A peak meter with hold. Redraws at 30 fps from a `TimelineView`, so it costs nothing once
/// the panel closes and the view is gone.
struct MeterBar: View {
    let source: MeterSource
    var axis: Axis = .vertical
    var thickness: CGFloat = 6
    /// Two bars, left and right.
    var stereo = false
    var look: MeterLook?

    @Environment(\.djTokens) private var tokens
    @Environment(\.metersLive) private var live

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !live)) { context in
            let frame = source.bank.frame(source.id, at: context.date.timeIntervalSinceReferenceDate)
            Canvas { gc, size in
                MeterPainter(tokens: tokens, look: look ?? tokens.meter, vertical: axis == .vertical)
                    .draw(frame, stereo: stereo, in: CGRect(origin: .zero, size: size), context: &gc)
            }
        }
        .frame(width: axis == .vertical ? (stereo ? thickness * 2 + 2 : thickness) : nil,
               height: axis == .vertical ? nil : (stereo ? thickness * 2 + 2 : thickness))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Draws meters in the three template styles. Flat fills only.
struct MeterPainter {
    let tokens: ThemeTokens
    let look: MeterLook
    let vertical: Bool

    func draw(_ frame: MeterFrame, stereo: Bool, in rect: CGRect, context: inout GraphicsContext) {
        guard stereo else {
            bar(level: frame.level, hold: frame.hold, in: rect, context: &context)
            return
        }
        let gap: CGFloat = 2
        if vertical {
            let width = (rect.width - gap) / 2
            bar(level: frame.left, hold: frame.holdLeft,
                in: CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height), context: &context)
            bar(level: frame.right, hold: frame.holdRight,
                in: CGRect(x: rect.minX + width + gap, y: rect.minY, width: width, height: rect.height), context: &context)
        } else {
            let height = (rect.height - gap) / 2
            bar(level: frame.left, hold: frame.holdLeft,
                in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height), context: &context)
            bar(level: frame.right, hold: frame.holdRight,
                in: CGRect(x: rect.minX, y: rect.minY + height + gap, width: rect.width, height: height), context: &context)
        }
    }

    private func bar(level: Float, hold: Float, in rect: CGRect, context: inout GraphicsContext) {
        switch look {
        case .bar: continuous(level: level, hold: hold, in: rect, context: &context)
        case .segments: segmented(level: level, hold: hold, in: rect, step: 5, gap: 1.5, radius: 0, context: &context)
        case .led: segmented(level: level, hold: hold, in: rect, step: 7, gap: 2, radius: 1, context: &context)
        }
    }

    private func continuous(level: Float, hold: Float, in rect: CGRect, context: inout GraphicsContext) {
        let radius = min(rect.width, rect.height) / 2
        context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(tokens.meterOff))
        let length = vertical ? rect.height : rect.width
        let filled = CGFloat(level) * length
        if filled > 0.5 {
            let fill = vertical
                ? CGRect(x: rect.minX, y: rect.maxY - filled, width: rect.width, height: filled)
                : CGRect(x: rect.minX, y: rect.minY, width: filled, height: rect.height)
            context.fill(Path(roundedRect: fill, cornerRadius: radius), with: .color(tokens.meterColor(level)))
        }
        if hold > 0.02 {
            let at = CGFloat(hold) * length
            let mark = vertical
                ? CGRect(x: rect.minX, y: rect.maxY - at, width: rect.width, height: 2)
                : CGRect(x: rect.minX + at - 2, y: rect.minY, width: 2, height: rect.height)
            context.fill(Path(mark), with: .color(tokens.meterColor(hold)))
        }
    }

    private func segmented(level: Float, hold: Float, in rect: CGRect, step: CGFloat, gap: CGFloat,
                           radius: CGFloat, context: inout GraphicsContext) {
        let length = vertical ? rect.height : rect.width
        let count = max(6, Int(length / step))
        let size = (length - gap * CGFloat(count - 1)) / CGFloat(count)
        guard size > 0 else { return }
        let holdIndex = hold > 0.02 ? min(count - 1, Int(hold * Float(count))) : -1
        for index in 0..<count {
            let top = Float(index + 1) / Float(count)
            let lit = top <= level + 0.5 / Float(count) || index == holdIndex
            let offset = CGFloat(index) * (size + gap)
            let cell = vertical
                ? CGRect(x: rect.minX, y: rect.maxY - offset - size, width: rect.width, height: size)
                : CGRect(x: rect.minX + offset, y: rect.minY, width: size, height: rect.height)
            let color = lit ? tokens.meterColor(top) : tokens.meterOff
            context.fill(Path(roundedRect: cell, cornerRadius: radius), with: .color(color))
        }
    }
}

/// The last three seconds of level as a scrolling waveform. Newest on the right.
struct LevelHistory: View {
    let source: MeterSource
    var tint: Color
    /// Mirrored around the middle like a waveform, or rising from the bottom.
    var mirrored = true
    var barWidth: CGFloat = 3

    @Environment(\.metersLive) private var live

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !live)) { context in
            let values = source.bank.history(source.id, at: context.date.timeIntervalSinceReferenceDate)
            Canvas { gc, size in
                let slots = max(1, Int(size.width / barWidth))
                let shown = values.suffix(slots)
                let start = size.width - CGFloat(shown.count) * barWidth
                for (offset, value) in shown.enumerated() {
                    let height = max(1, CGFloat(value) * size.height)
                    let x = start + CGFloat(offset) * barWidth
                    let rect = mirrored
                        ? CGRect(x: x, y: (size.height - height) / 2, width: max(1, barWidth - 1), height: height)
                        : CGRect(x: x, y: size.height - height, width: max(1, barWidth - 1), height: height)
                    let fade = 0.3 + 0.7 * Double(offset + 1) / Double(max(1, shown.count))
                    gc.fill(Path(rect), with: .color(tint.opacity(fade)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
