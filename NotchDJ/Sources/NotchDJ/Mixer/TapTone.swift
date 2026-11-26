// Based on NotchBar (https://github.com/srisanthosh/NotchBar), GPLv3.
// Original copyright remains with the NotchBar authors. Notch DJ changes are under the same license.
import Darwin
import Foundation

/// One biquad, normalized so a0 is 1. Plain floats, no heap.
struct BiquadCoeff: Sendable {
    var b0: Float = 1
    var b1: Float = 0
    var b2: Float = 0
    var a1: Float = 0
    var a2: Float = 0
    static let identity = BiquadCoeff()
}

struct BiquadState {
    var z1: Float = 0
    var z2: Float = 0
}

/// Filter coefficients for one app. `filters` is 0 when HI/MID/LOW/FILTER are flat.
struct ToneTarget: Sendable {
    var hi = BiquadCoeff.identity
    var mid = BiquadCoeff.identity
    var low = BiquadCoeff.identity
    var filter = BiquadCoeff.identity
    var makeup: Float = 1
    var filters: Int32 = 0
    static let bypass = ToneTarget()
}

/// Render-thread state. No other thread reads or writes it.
struct ToneRuntime {
    var hiL = BiquadState(), hiR = BiquadState()
    var midL = BiquadState(), midR = BiquadState()
    var lowL = BiquadState(), lowR = BiquadState()
    var filtL = BiquadState(), filtR = BiquadState()
    var hi = BiquadCoeff.identity
    var mid = BiquadCoeff.identity
    var low = BiquadCoeff.identity
    var filter = BiquadCoeff.identity
    var makeup: Float = 1
    var mix: Float = 0
    var alpha: Float = 0.001
}

/// Two coefficient slots plus a generation word.
/// Even generation: slot (generation/2 % 2) is stable. Odd: the engine queue is writing.
/// `Synchronization.Atomic` needs macOS 15, so the generation word uses the same OSAtomic
/// barrier already used for the gain target.
struct ToneMailbox {
    var generation: Int32 = 0
    var pad: Int32 = 0
    var slot0 = ToneTarget.bypass
    var slot1 = ToneTarget.bypass
}

enum ToneMath {
    static func target(for tone: DeckTone, sampleRate: Float) -> ToneTarget {
        let rate = sampleRate > 1000 ? sampleRate : 48_000
        var built = ToneTarget.bypass
        let hiDB = bandDB(tone.hi)
        let midDB = bandDB(tone.mid)
        let lowDB = bandDB(tone.low)
        built.hi = shelf(high: true, frequency: 4_000, db: hiDB, sampleRate: rate)
        built.mid = peak(frequency: 1_000, db: midDB, q: 0.7, sampleRate: rate)
        built.low = shelf(high: false, frequency: 250, db: lowDB, sampleRate: rate)
        if let filter = filterCoeff(tone.filter, sampleRate: rate) {
            built.filter = filter
        }
        built.makeup = pow(10, ((Float(tone.gain) - 0.5) * 24) / 20)
        let filters = !near(hiDB, 0) || !near(midDB, 0) || !near(lowDB, 0) || abs(tone.filter - 0.5) >= 0.02
        built.filters = filters ? 1 : 0
        if !filters && near(built.makeup, 1) { return .bypass }
        return built
    }

    /// ±12 dB through the knob, and a kill at the bottom.
    private static func bandDB(_ knob: Double) -> Float {
        if knob <= 0.02 { return -48 }
        if knob < 0.5 {
            let t = Float((knob - 0.02) / (0.5 - 0.02))
            return -12 + t * 12
        }
        return Float((knob - 0.5) / 0.5) * 12
    }

    private static func near(_ value: Float, _ other: Float) -> Bool {
        abs(value - other) < 0.05
    }

    private static func filterCoeff(_ knob: Double, sampleRate: Float) -> BiquadCoeff? {
        let delta = knob - 0.5
        if abs(delta) < 0.02 { return nil }
        if delta < 0 {
            let t = Float(((-delta) - 0.02) / 0.48)
            let hz = 18_000 * pow(200 / 18_000, min(1, max(0, t)))
            return lowpass(frequency: hz, sampleRate: sampleRate)
        }
        let t = Float((delta - 0.02) / 0.48)
        let hz = 200 * pow(18_000 / 200, min(1, max(0, t)))
        return highpass(frequency: hz, sampleRate: sampleRate)
    }

    private static func lowpass(frequency: Float, sampleRate: Float) -> BiquadCoeff {
        let (w, alpha, cosw) = omega(frequency, q: 0.707, sampleRate: sampleRate)
        _ = w
        let b0 = (1 - cosw) / 2
        let b1 = 1 - cosw
        let b2 = b0
        return normalize(b0: b0, b1: b1, b2: b2, a0: 1 + alpha, a1: -2 * cosw, a2: 1 - alpha)
    }

    private static func highpass(frequency: Float, sampleRate: Float) -> BiquadCoeff {
        let (_, alpha, cosw) = omega(frequency, q: 0.707, sampleRate: sampleRate)
        let b0 = (1 + cosw) / 2
        let b1 = -(1 + cosw)
        let b2 = b0
        return normalize(b0: b0, b1: b1, b2: b2, a0: 1 + alpha, a1: -2 * cosw, a2: 1 - alpha)
    }

    private static func peak(frequency: Float, db: Float, q: Float, sampleRate: Float) -> BiquadCoeff {
        if near(db, 0) { return .identity }
        let a = pow(10, db / 40)
        let (_, alpha, cosw) = omega(frequency, q: q, sampleRate: sampleRate)
        return normalize(b0: 1 + alpha * a, b1: -2 * cosw, b2: 1 - alpha * a,
                         a0: 1 + alpha / a, a1: -2 * cosw, a2: 1 - alpha / a)
    }

    private static func shelf(high: Bool, frequency: Float, db: Float, sampleRate: Float) -> BiquadCoeff {
        if near(db, 0) { return .identity }
        let a = pow(10, db / 40)
        let (w, _, cosw) = omega(frequency, q: 0.707, sampleRate: sampleRate)
        _ = w
        let sinw = sin(2 * Float.pi * min(frequency, sampleRate * 0.45) / sampleRate)
        let alpha = sinw / 2 * sqrt((a + 1 / a) * 0 + 2)
        let two = 2 * sqrt(a) * alpha
        if high {
            return normalize(
                b0: a * ((a + 1) + (a - 1) * cosw + two),
                b1: -2 * a * ((a - 1) + (a + 1) * cosw),
                b2: a * ((a + 1) + (a - 1) * cosw - two),
                a0: (a + 1) - (a - 1) * cosw + two,
                a1: 2 * ((a - 1) - (a + 1) * cosw),
                a2: (a + 1) - (a - 1) * cosw - two)
        }
        return normalize(
            b0: a * ((a + 1) - (a - 1) * cosw + two),
            b1: 2 * a * ((a - 1) - (a + 1) * cosw),
            b2: a * ((a + 1) - (a - 1) * cosw - two),
            a0: (a + 1) + (a - 1) * cosw + two,
            a1: -2 * ((a - 1) + (a + 1) * cosw),
            a2: (a + 1) + (a - 1) * cosw - two)
    }

    private static func omega(_ frequency: Float, q: Float, sampleRate: Float) -> (Float, Float, Float) {
        let hz = min(max(frequency, 20), sampleRate * 0.45)
        let w = 2 * Float.pi * hz / sampleRate
        let s = sin(w)
        let c = cos(w)
        return (w, s / (2 * max(q, 0.05)), c)
    }

    private static func normalize(b0: Float, b1: Float, b2: Float, a0: Float, a1: Float, a2: Float) -> BiquadCoeff {
        let scale = a0 == 0 ? 1 : 1 / a0
        return BiquadCoeff(b0: b0 * scale, b1: b1 * scale, b2: b2 * scale, a1: a1 * scale, a2: a2 * scale)
    }
}

func tonePublish(_ target: ToneTarget, _ box: UnsafeMutablePointer<ToneMailbox>) {
    let gen = UnsafeMutableRawPointer(box).assumingMemoryBound(to: Int32.self)
    var g = OSAtomicAdd32Barrier(0, gen)
    if g & 1 == 1 {
        _ = OSAtomicCompareAndSwap32Barrier(g, g + 1, gen)
        g = OSAtomicAdd32Barrier(0, gen)
    }
    guard g & 1 == 0, OSAtomicCompareAndSwap32Barrier(g, g + 1, gen) else { return }
    let index = ((g / 2) + 1) & 1
    let offset = index == 0
        ? MemoryLayout<ToneMailbox>.offset(of: \.slot0)!
        : MemoryLayout<ToneMailbox>.offset(of: \.slot1)!
    UnsafeMutableRawPointer(box).advanced(by: offset).assumingMemoryBound(to: ToneTarget.self).pointee = target
    _ = OSAtomicCompareAndSwap32Barrier(g + 1, g + 2, gen)
}

func toneRead(_ box: UnsafeMutablePointer<ToneMailbox>, fallback: ToneTarget) -> ToneTarget {
    let gen = UnsafeMutableRawPointer(box).assumingMemoryBound(to: Int32.self)
    let g1 = OSAtomicAdd32Barrier(0, gen)
    if g1 & 1 == 1 { return fallback }
    let index = (g1 / 2) & 1
    let offset = index == 0
        ? MemoryLayout<ToneMailbox>.offset(of: \.slot0)!
        : MemoryLayout<ToneMailbox>.offset(of: \.slot1)!
    let copy = UnsafeMutableRawPointer(box).advanced(by: offset).assumingMemoryBound(to: ToneTarget.self).pointee
    let g2 = OSAtomicAdd32Barrier(0, gen)
    return g1 == g2 ? copy : fallback
}

struct ToneWork {
    var target = ToneTarget.bypass
    var hi = BiquadCoeff.identity
    var mid = BiquadCoeff.identity
    var low = BiquadCoeff.identity
    var filter = BiquadCoeff.identity
    var makeup: Float = 1
    var mix: Float = 0
    var alpha: Float = 0.001
    var hiL = BiquadState(), hiR = BiquadState()
    var midL = BiquadState(), midR = BiquadState()
    var lowL = BiquadState(), lowR = BiquadState()
    var filtL = BiquadState(), filtR = BiquadState()
    var live = false
}

func toneBegin(_ runtime: UnsafeMutablePointer<ToneRuntime>, _ box: UnsafeMutablePointer<ToneMailbox>) -> ToneWork {
    var work = ToneWork()
    let current = runtime.pointee
    work.hi = current.hi
    work.mid = current.mid
    work.low = current.low
    work.filter = current.filter
    work.makeup = current.makeup
    work.mix = current.mix
    work.alpha = current.alpha
    work.hiL = current.hiL
    work.hiR = current.hiR
    work.midL = current.midL
    work.midR = current.midR
    work.lowL = current.lowL
    work.lowR = current.lowR
    work.filtL = current.filtL
    work.filtR = current.filtR
    work.target = toneRead(box, fallback: ToneTarget(
        hi: work.hi, mid: work.mid, low: work.low, filter: work.filter,
        makeup: work.makeup, filters: work.mix > 0.5 ? 1 : 0))
    work.live = true
    return work
}

func toneStep(_ work: inout ToneWork) {
    let a = work.alpha
    approachCoeff(&work.hi, work.target.hi, a)
    approachCoeff(&work.mid, work.target.mid, a)
    approachCoeff(&work.low, work.target.low, a)
    approachCoeff(&work.filter, work.target.filter, a)
    work.makeup += (work.target.makeup - work.makeup) * a
    let aim: Float = work.target.filters == 0 ? 0 : 1
    work.mix += (aim - work.mix) * a
}

func toneSample(_ x: Float, channel: Int, work: inout ToneWork) -> Float {
    guard work.mix > 0.0008 else { return flush(x * work.makeup) }
    var y = x
    if channel == 0 {
        y = biq(y, work.hi, &work.hiL)
        y = biq(y, work.mid, &work.midL)
        y = biq(y, work.low, &work.lowL)
        y = biq(y, work.filter, &work.filtL)
    } else {
        y = biq(y, work.hi, &work.hiR)
        y = biq(y, work.mid, &work.midR)
        y = biq(y, work.low, &work.lowR)
        y = biq(y, work.filter, &work.filtR)
    }
    return flush(x + (y - x) * work.mix) * work.makeup
}

func toneEnd(_ work: ToneWork, _ runtime: UnsafeMutablePointer<ToneRuntime>) {
    var next = runtime.pointee
    next.hi = work.hi
    next.mid = work.mid
    next.low = work.low
    next.filter = work.filter
    next.makeup = work.makeup
    next.mix = work.mix
    next.hiL = work.hiL
    next.hiR = work.hiR
    next.midL = work.midL
    next.midR = work.midR
    next.lowL = work.lowL
    next.lowR = work.lowR
    next.filtL = work.filtL
    next.filtR = work.filtR
    runtime.pointee = next
}

private func approachCoeff(_ cur: inout BiquadCoeff, _ target: BiquadCoeff, _ alpha: Float) {
    cur.b0 += (target.b0 - cur.b0) * alpha
    cur.b1 += (target.b1 - cur.b1) * alpha
    cur.b2 += (target.b2 - cur.b2) * alpha
    cur.a1 += (target.a1 - cur.a1) * alpha
    cur.a2 += (target.a2 - cur.a2) * alpha
}

private func biq(_ x: Float, _ c: BiquadCoeff, _ s: inout BiquadState) -> Float {
    let y = c.b0 * x + s.z1
    s.z1 = flush(c.b1 * x - c.a1 * y + s.z2)
    s.z2 = flush(c.b2 * x - c.a2 * y)
    return y
}

private func flush(_ value: Float) -> Float {
    value.magnitude < 1e-15 ? 0 : value
}
