import SwiftUI

enum TEColor {
    static let background = Color(red: 23 / 255, green: 23 / 255, blue: 25 / 255)
    static let track = Color(red: 14 / 255, green: 14 / 255, blue: 16 / 255)
    static let accent = Color(red: 1, green: 85 / 255, blue: 0)
    static let panel = Color(red: 42 / 255, green: 42 / 255, blue: 46 / 255)
    static let secondary = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
    static let text = Color(red: 242 / 255, green: 242 / 255, blue: 242 / 255)
    static let deckA = Color(red: 0, green: 212 / 255, blue: 1)
    static let deckB = Color(red: 1, green: 122 / 255, blue: 26 / 255)
}

struct TEMicroLabel: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .medium))
            .tracking(0.5)
            .foregroundStyle(TEColor.secondary)
            .lineLimit(1)
    }
}

struct TEValue: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(TEColor.text)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// Flat circle. A thin arc and a dot show the value. Drag vertically or scroll.
struct FlatKnob: View {
    var value: Double
    var tint: Color
    var diameter: CGFloat = 56
    var enabled: Bool = true
    /// Black disc with a light ring. Used for the LOW band.
    var filled: Bool = false
    /// Extra arc for the master peak. 0 hides it.
    var meter: Float = 0
    var onChange: (Double) -> Void
    @State private var origin: Double?

    var body: some View {
        let clamped = min(1, max(0, value))
        ZStack {
            Circle().fill(filled ? Color.black : Color.clear)
            Circle().stroke(filled ? TEColor.text : TEColor.panel, lineWidth: 2)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if meter > 0.01 {
                Circle()
                    .trim(from: 0, to: CGFloat(min(1, meter)))
                    .stroke(tint.opacity(0.45), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                    .padding(3)
                    .rotationEffect(.degrees(-90))
            }
            Circle()
                .fill(TEColor.text)
                .frame(width: 4, height: 4)
                .offset(y: -diameter * 0.32)
                .rotationEffect(.degrees(-140 + clamped * 280))
        }
        .frame(width: diameter, height: diameter)
        .opacity(enabled ? 1 : 0.4)
        .gesture(DragGesture(minimumDistance: 2).onChanged { drag in
            guard enabled else { return }
            let base = origin ?? clamped
            if origin == nil { origin = base }
            let next = base + Double(-drag.translation.height / 140)
            onChange(min(1, max(0, next)))
        }.onEnded { _ in
            origin = nil
        })
        .background(ScrollWheelCatcher { delta in
            guard enabled else { return }
            let step = delta > 0 ? 0.02 : -0.02
            onChange(min(1, max(0, clamped + step)))
        })
        .accessibilityLabel("Knob")
    }
}

/// Long-throw fader: 4 pt track, ticks every 10%, flat cap with one accent line.
struct TEFader: View {
    var level: Int
    var maxLevel: Int
    var muted: Bool
    var tint: Color = TEColor.accent
    var onChange: (Int) -> Void
    @State private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let fraction = CGFloat(min(maxLevel, max(0, level))) / CGFloat(max(maxLevel, 1))
            let travel = max(geo.size.height - 12, 1)
            let y = travel * (1 - (muted ? 0 : fraction))
            ZStack(alignment: .top) {
                Capsule().fill(TEColor.track).frame(width: 4)
                tickColumn(height: geo.size.height)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(TEColor.panel)
                    .frame(width: 28, height: 12)
                    .overlay(Rectangle().fill(tint).frame(width: 16, height: 1))
                    .offset(y: y)
                    .animation(dragging || reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: level)
                    .animation(dragging || reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: muted)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2).onChanged { drag in
                dragging = true
                let next = 1 - Double(min(travel, max(0, drag.location.y - 6)) / travel)
                onChange(min(maxLevel, max(0, Int((next * Double(maxLevel)).rounded()))))
            }.onEnded { _ in
                dragging = false
            })
            .background(ScrollWheelCatcher { delta in
                let step = delta > 0 ? 2 : -2
                onChange(min(maxLevel, max(0, level + step)))
            })
        }
    }

    private func tickColumn(height: CGFloat) -> some View {
        Canvas { context, size in
            var mark = 0
            while mark <= 10 {
                let y = size.height * CGFloat(mark) / 10
                let line = Path { path in
                    path.move(to: CGPoint(x: size.width * 0.5 - 7, y: y))
                    path.addLine(to: CGPoint(x: size.width * 0.5 + 7, y: y))
                }
                context.stroke(line, with: .color(TEColor.secondary.opacity(0.45)), lineWidth: 1)
                mark += 1
            }
        }
        .frame(height: height)
        .allowsHitTesting(false)
    }
}

struct TESquareButton: View {
    var title: String
    var active: Bool
    var tint: Color = TEColor.accent
    var width: CGFloat = 20
    var action: () -> Void
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(active ? Color.black : TEColor.text)
                .frame(width: width, height: 20)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(active ? tint : TEColor.panel))
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.white.opacity(hover ? 0.28 : 0.08), lineWidth: 1))
                .brightness(hover && !active ? 0.12 : 0)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: active)
    }
}

struct CurvePills: View {
    @ObservedObject var mixer: AppVolumeMixer

    var body: some View {
        HStack(spacing: 8) {
            ForEach(CrossCurve.allCases) { curve in
                Button {
                    mixer.crossCurve = curve
                } label: {
                    Text(curve.title)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(mixer.crossCurve == curve ? Color.black : TEColor.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 18)
                        .background(Capsule().fill(mixer.crossCurve == curve ? TEColor.accent : TEColor.panel))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct TECrossfader: View {
    @ObservedObject var mixer: AppVolumeMixer
    var tint: Color = TEColor.accent
    @State private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            endMark(isA: true)
            track
            endMark(isA: false)
        }
    }

    private var track: some View {
        GeometryReader { geo in
            let cap: CGFloat = 18
            let travel = max(geo.size.width - cap, 1)
            let x = travel * mixer.crossfade
            ZStack(alignment: .leading) {
                Capsule().fill(TEColor.track).frame(height: 4)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(TEColor.panel)
                    .frame(width: cap, height: 10)
                    .overlay(Rectangle().fill(tint).frame(width: 10, height: 1))
                    .offset(x: x)
                    .animation(dragging || reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.8), value: mixer.crossfade)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                dragging = true
                let next = Double(min(travel, max(0, drag.location.x - cap / 2)) / travel)
                mixer.setCrossfade(next)
            }.onEnded { _ in
                dragging = false
            })
        }
        .frame(height: 16)
    }

    private func endMark(isA: Bool) -> some View {
        let current = isA ? mixer.crossA : mixer.crossB
        return Menu {
            ForEach(mixer.rows) { row in
                Button(MixerDisplayName.short(bundleID: row.id, fallback: row.name)) {
                    if isA { mixer.setCrossA(row.id) } else { mixer.setCrossB(row.id) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if isA { icon(current) }
                Text(isA ? "A" : "B")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(TEColor.secondary)
                if !isA { icon(current) }
            }
            .frame(width: 36)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 44)
    }

    @ViewBuilder private func icon(_ bundleID: String?) -> some View {
        if let bundleID, let image = MixerIcons.icon(for: bundleID) {
            Image(nsImage: image).resizable().frame(width: 14, height: 14)
        } else {
            RoundedRectangle(cornerRadius: 2).fill(TEColor.panel).frame(width: 14, height: 14)
        }
    }
}

/// Thin LED column. The view exists only while the mixer panel is on screen.
struct SegmentMeter: View {
    var peak: Float
    var rms: Float
    var tint: Color
    var dim: Bool = false
    @State private var hold = MeterHold()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30)) { timeline in
            let held = hold.note(peak, now: timeline.date)
            VStack(spacing: 2) {
                ForEach((0..<12).reversed(), id: \.self) { index in
                    let gate = Float(index + 1) / 12
                    RoundedRectangle(cornerRadius: 1)
                        .fill(segmentColor(gate: gate, held: held))
                        .frame(height: 4)
                }
            }
            .opacity(dim ? 0.35 : 1)
        }
        .frame(width: 6)
    }

    private func segmentColor(gate: Float, held: Float) -> Color {
        if peak >= gate { return tint }
        if rms >= gate { return tint.opacity(0.45) }
        if held >= gate { return TEColor.text.opacity(0.35) }
        return TEColor.track
    }
}

private final class MeterHold {
    private var value: Float = 0
    private var at = Date.distantPast

    func note(_ peak: Float, now: Date) -> Float {
        if peak >= value - 0.01 {
            value = peak
            at = now
            return value
        }
        let age = now.timeIntervalSince(at)
        if age < 1 { return value }
        let fall = Float(min(1, (age - 1) / 1))
        return max(peak, value * (1 - fall))
    }
}
