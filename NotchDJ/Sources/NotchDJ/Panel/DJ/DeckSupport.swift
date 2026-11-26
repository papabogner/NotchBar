import SwiftUI

/// The tone controls a deck can show.
enum ToneBand: CaseIterable, Identifiable, Sendable {
    case gain, hi, mid, low, filter

    static let eq: [ToneBand] = [.hi, .mid, .low]

    var id: Self { self }

    var label: String {
        switch self {
        case .gain: return String(localized: "GAIN")
        case .hi: return String(localized: "HI")
        case .mid: return String(localized: "MID")
        case .low: return String(localized: "LOW")
        case .filter: return String(localized: "FILTER")
        }
    }

    var isEQ: Bool { self == .hi || self == .mid || self == .low }
}

extension DeckTone {
    subscript(band: ToneBand) -> Double {
        get {
            switch band {
            case .gain: return gain
            case .hi: return hi
            case .mid: return mid
            case .low: return low
            case .filter: return filter
            }
        }
        set {
            switch band {
            case .gain: gain = newValue
            case .hi: hi = newValue
            case .mid: mid = newValue
            case .low: low = newValue
            case .filter: filter = newValue
            }
        }
    }
}

/// Value text for the tone knobs. Uses the same mappings as the render path.
enum ToneText {
    static func value(_ band: ToneBand, _ knob: Double) -> String {
        switch band {
        case .gain:
            return decibels(ToneMath.makeupDB(knob))
        case .filter:
            switch ToneMath.filterMode(knob) {
            case .off: return String(localized: "OFF")
            case .lowPass(let hz): return "LP " + hertz(hz)
            case .highPass(let hz): return "HP " + hertz(hz)
            }
        case .hi, .mid, .low:
            return ToneMath.isKill(knob) ? String(localized: "KILL") : decibels(ToneMath.bandGain(knob))
        }
    }

    static func level(_ fader: Double) -> String { "\(Int((fader * 150).rounded()))%" }

    private static func decibels(_ db: Float) -> String {
        abs(db) < 0.25 ? "0 dB" : String(format: "%+.1f dB", db)
    }

    private static func hertz(_ hz: Float) -> String {
        hz >= 1000 ? String(format: "%.1f kHz", hz / 1000) : "\(Int(hz.rounded())) Hz"
    }
}

/// Bindings for one deck. Everything goes through the mixer, which hands audio work to its engine queue.
@MainActor
struct DeckControls {
    let mixer: AppVolumeMixer
    let side: DeckSide

    static let unity = 100.0 / 150

    var appID: String? { mixer.deckID(side) }
    var row: AppVolumeRow? { mixer.deckRow(side) }
    var isLoaded: Bool { row != nil }
    var isPlaying: Bool { row.map { $0.playing && !$0.muted } ?? false }
    var cueOn: Bool { row.map { mixer.soloID == $0.id } ?? false }
    var meter: MeterSource? { appID.map { MeterSource(bank: mixer.meters, id: $0) } }

    var name: String {
        guard let row else { return String(localized: "Empty") }
        return MixerDisplayName.short(bundleID: row.id, fallback: row.name)
    }

    var status: String {
        guard let row else { return String(localized: "No app") }
        if row.muted { return String(localized: "Muted") }
        if cueOn { return String(localized: "Cue") }
        return row.playing ? String(localized: "Playing") : String(localized: "Silent")
    }

    var level: Binding<Double> {
        let mixer = mixer
        let side = side
        return Binding(get: { Double(mixer.deckRow(side)?.level ?? 100) / 150 },
                       set: { mixer.setDeckLevel(side, Int(($0 * 150).rounded())) })
    }

    func tone(_ band: ToneBand) -> Binding<Double> {
        let mixer = mixer
        let side = side
        return Binding(get: { mixer.tone(side)[band] },
                       set: { value in
                           var tone = mixer.tone(side)
                           tone[band] = value
                           mixer.setTone(side, tone)
                       })
    }

    func toggleCue() { mixer.toggleCue(side) }
}

/// A tone knob for a deck, with the right detents and value text.
struct ToneKnob: View {
    let deck: DeckControls
    let band: ToneBand
    var size: CGFloat
    var tint: Color?
    var look: KnobLook?

    var body: some View {
        let band = band
        DJKnob(value: deck.tone(band), label: band.label, size: size, defaultValue: 0.5, bipolar: true,
               kill: band.isEQ, tint: tint, look: look, format: { ToneText.value(band, $0) })
    }
}

/// The volume fader for a deck, with its meter.
struct DeckFader: View {
    let deck: DeckControls
    var axis: Axis = .vertical
    var tint: Color?
    var look: FaderLook?
    var showsMeter = true

    var body: some View {
        DJFader(value: deck.level, label: String(localized: "Deck \(deck.side.letter) volume"), axis: axis,
                defaultValue: DeckControls.unity, detents: [DeckControls.unity], tint: tint, look: look,
                meter: showsMeter ? deck.meter : nil, format: ToneText.level)
    }
}

struct CueButton: View {
    let deck: DeckControls
    var width: CGFloat = 46
    var height: CGFloat = 26

    @Environment(\.djTokens) private var tokens

    var body: some View {
        PadButton(title: String(localized: "CUE"), active: deck.cueOn, tint: tokens.deck(deck.side),
                  width: width, height: height,
                  help: String(localized: "Hear only this deck")) {
            deck.toggleCue()
        }
        .disabled(!deck.isLoaded)
    }
}

/// The deck's app with a menu to change it.
struct DeckTitle: View {
    let deck: DeckControls
    /// Nil hides the app icon, for layouts that show artwork beside the title.
    var iconSize: CGFloat? = 20
    var showsLetter = true

    @Environment(\.djTokens) private var tokens

    var body: some View {
        DeckSourceMenu(side: deck.side) {
            HStack(spacing: 8) {
                if showsLetter {
                    Text(verbatim: deck.side.letter)
                        .djFont(.label)
                        .foregroundStyle(tokens.onAccent)
                        .frame(width: 18, height: 18)
                        .background(RoundedRectangle(cornerRadius: tokens.controlRadius, style: .continuous)
                            .fill(tokens.deck(deck.side)))
                }
                if let id = deck.appID, let iconSize {
                    AppIconView(bundleID: id, size: iconSize)
                }
                Text(verbatim: deck.name)
                    .djFont(.title)
                    .lineLimit(1)
                    .foregroundStyle(deck.isLoaded ? tokens.text : tokens.tertiary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tokens.tertiary)
            }
            .contentShape(Rectangle())
        }
        .help(Text("Choose the app on this deck"))
    }
}

/// The deck's artwork when its app is the one in Now Playing, otherwise its icon.
struct DeckArtwork: View {
    let deck: DeckControls
    let size: CGFloat
    var radius: CGFloat?

    @EnvironmentObject private var now: NowPlayingMonitor
    @Environment(\.heroNamespace) private var hero

    var body: some View {
        let playingHere = deck.appID != nil && now.entry?.source.bundleID == deck.appID
        ArtworkView(image: playingHere ? now.artwork : nil, bundleID: deck.appID, size: size, radius: radius)
            .hero("artwork", hero, enabled: playingHere)
    }
}

/// SMOOTH, DIP and CUT.
struct CurvePicker: View {
    var width: CGFloat = 52

    @EnvironmentObject private var mixer: AppVolumeMixer
    @Environment(\.djTokens) private var tokens

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CrossCurve.allCases) { curve in
                PadButton(title: curve.title, active: mixer.crossCurve == curve, tint: tokens.accent,
                          width: width, height: 22, help: String(localized: "Crossfader curve")) {
                    mixer.crossCurve = curve
                }
            }
        }
    }
}

/// The crossfader, bound to the mixer.
struct DeckCrossfader: View {
    var height: CGFloat = 34
    var showsLegends = true

    @EnvironmentObject private var mixer: AppVolumeMixer

    var body: some View {
        Crossfader(value: Binding(get: { mixer.crossfade }, set: { mixer.setCrossfade($0) }),
                   height: height, showsLegends: showsLegends)
    }
}

/// Shown on a deck with no app.
struct EmptyDeck: View {
    let side: DeckSide

    @Environment(\.djTokens) private var tokens

    var body: some View {
        DeckSourceMenu(side: side) {
            VStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 20, weight: .light))
                Text("Load an app")
                    .djFont(.caption)
            }
            .foregroundStyle(tokens.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
    }
}

extension View {
    /// Dims and locks the controls of a deck with no app.
    func deckEnabled(_ enabled: Bool) -> some View {
        opacity(enabled ? 1 : 0.35).allowsHitTesting(enabled)
    }
}

/// The level history of a deck, or a flat line when it's empty.
struct DeckWave: View {
    let deck: DeckControls
    var mirrored = true
    var barWidth: CGFloat = 3

    @Environment(\.djTokens) private var tokens

    var body: some View {
        if let meter = deck.meter {
            LevelHistory(source: meter, tint: tokens.deck(deck.side), mirrored: mirrored, barWidth: barWidth)
        } else {
            Rectangle()
                .fill(tokens.line)
                .frame(height: 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
