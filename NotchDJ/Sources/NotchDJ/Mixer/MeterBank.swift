import Foundation

/// The meter scale and its timing. Levels are fractions of a 60 dB scale.
enum MeterScale {
    static let floorDB: Float = -60
    /// Fall after a peak, per second: 26 dB.
    static let release: Float = 26 / 60
    static let holdTime: TimeInterval = 1.0
    /// Fall of the held peak once the hold is over, per second: 14 dB.
    static let holdFall: Float = 14 / 60
    static let historyLength = 96

    /// Linear amplitude to 0...1.
    static func normalized(_ amplitude: Float) -> Float {
        guard amplitude > 0.000_001 else { return 0 }
        let db = 20 * log10f(amplitude)
        return min(1, max(0, (db - floorDB) / -floorDB))
    }
}

/// One meter reading after ballistics. All values are 0...1 on `MeterScale`.
struct MeterFrame: Equatable {
    var left: Float = 0
    var right: Float = 0
    var holdLeft: Float = 0
    var holdRight: Float = 0

    var level: Float { max(left, right) }
    var hold: Float { max(holdLeft, holdRight) }

    static let silent = MeterFrame()
}

/// Instant attack, linear release, held peak. Decay is computed at read time, so a meter
/// keeps falling smoothly when its readings stop.
struct MeterChannel {
    private var value: Float = 0
    private var at: TimeInterval = 0
    private var hold: Float = 0
    private var holdAt: TimeInterval = 0

    mutating func push(_ input: Float, now: TimeInterval) {
        let current = level(at: now)
        value = max(input, current)
        at = now
        if input >= holdLevel(at: now) {
            hold = input
            holdAt = now
        }
    }

    func level(at now: TimeInterval) -> Float {
        max(0, value - Float(max(0, now - at)) * MeterScale.release)
    }

    func holdLevel(at now: TimeInterval) -> Float {
        let age = now - holdAt
        if age <= MeterScale.holdTime { return hold }
        return max(0, hold - Float(age - MeterScale.holdTime) * MeterScale.holdFall)
    }
}

/// A fixed ring of recent levels, oldest first when read.
struct LevelRing {
    private var values = [Float](repeating: 0, count: MeterScale.historyLength)
    private var head = 0

    mutating func append(_ value: Float) {
        values[head] = value
        head = (head + 1) % values.count
    }

    var ordered: [Float] { Array(values[head...]) + Array(values[..<head]) }
}

/// Meter state for the panel. The engine feeds it at up to 30 Hz while the panel is open, and
/// meter views read it from a `TimelineView`. It is not observable on purpose: new readings
/// never re-render the panel, only the meters that draw them.
@MainActor
final class MeterBank {
    private struct Entry {
        var left = MeterChannel()
        var right = MeterChannel()
        var history = LevelRing()
        var updated: TimeInterval = 0
    }

    /// Previews draw made-up levels so templates look alive without any audio.
    let simulated: Bool
    private var entries: [String: Entry] = [:]
    private var master = Entry()

    init(simulated: Bool = false) {
        self.simulated = simulated
    }

    nonisolated static var now: TimeInterval { Date.timeIntervalSinceReferenceDate }

    func ingest(_ readings: [String: TapMeter], now: TimeInterval) {
        var masterLeft: Float = 0
        var masterRight: Float = 0
        for (id, reading) in readings {
            let left = MeterScale.normalized(reading.left)
            let right = MeterScale.normalized(reading.right)
            var entry = entries[id] ?? Entry()
            entry.left.push(left, now: now)
            entry.right.push(right, now: now)
            entry.history.append(max(left, right))
            entry.updated = now
            entries[id] = entry
            masterLeft = max(masterLeft, reading.left)
            masterRight = max(masterRight, reading.right)
        }
        let left = MeterScale.normalized(masterLeft)
        let right = MeterScale.normalized(masterRight)
        master.left.push(left, now: now)
        master.right.push(right, now: now)
        master.history.append(max(left, right))
        master.updated = now
        entries = entries.filter { now - $0.value.updated < 5 }
    }

    /// One app's meter, or the master (the loudest app) for nil.
    func frame(_ id: String?, at now: TimeInterval) -> MeterFrame {
        if simulated { return Self.fake(seed: id.map(Self.seed) ?? 0.37, at: now) }
        guard let id else { return Self.frame(master, at: now) }
        guard let entry = entries[id] else { return .silent }
        return Self.frame(entry, at: now)
    }

    /// Recent levels, oldest first. Always `MeterScale.historyLength` values. Nil is the master.
    func history(_ id: String?, at now: TimeInterval) -> [Float] {
        if simulated {
            let seed = id.map(Self.seed) ?? 0.37
            return (0..<MeterScale.historyLength).map { index in
                let age = Double(MeterScale.historyLength - 1 - index) / 30
                return Self.fake(seed: seed, at: now - age).level
            }
        }
        guard let id else { return master.history.ordered }
        return entries[id]?.history.ordered ?? Self.emptyHistory
    }

    func clear() {
        entries = [:]
        master = Entry()
    }

    nonisolated private static var emptyHistory: [Float] { [Float](repeating: 0, count: MeterScale.historyLength) }

    nonisolated private static func frame(_ entry: Entry, at now: TimeInterval) -> MeterFrame {
        MeterFrame(left: entry.left.level(at: now), right: entry.right.level(at: now),
                   holdLeft: entry.left.holdLevel(at: now), holdRight: entry.right.holdLevel(at: now))
    }

    nonisolated private static func seed(_ id: String) -> Double {
        let sum = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Double(sum % 997) / 997
    }

    /// A steady beat with a little movement, for previews only.
    nonisolated private static func fake(seed: Double, at now: TimeInterval) -> MeterFrame {
        let beat = pow(max(0, sin(now * .pi * 4 + seed * 9)), 6)
        let drift = 0.5 + 0.18 * sin(now * (0.7 + seed) + seed * 20)
        let left = Float(min(0.98, max(0, drift + 0.3 * beat)))
        let right = Float(min(0.98, max(0, drift * 0.94 + 0.28 * beat)))
        let hold = min(1, max(left, right) + 0.06)
        return MeterFrame(left: left, right: right, holdLeft: hold, holdRight: hold)
    }
}
