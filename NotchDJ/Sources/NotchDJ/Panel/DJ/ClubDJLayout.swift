import SwiftUI

/// Two platters, the EQ in the middle and a big crossfader.
struct ClubDJLayout: View {
    @EnvironmentObject private var mixer: AppVolumeMixer

    var body: some View {
        let a = DeckControls(mixer: mixer, side: .a)
        let b = DeckControls(mixer: mixer, side: .b)
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                ClubDeck(deck: a)
                HStack(alignment: .top, spacing: 10) {
                    ClubStrip(deck: a)
                    ClubStrip(deck: b)
                }
                ClubDeck(deck: b)
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 16) {
                DeckCrossfader(height: 44)
                CurvePicker(width: 50)
            }
        }
    }
}

private struct ClubDeck: View {
    let deck: DeckControls

    @Environment(\.djTokens) private var tokens

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                DeckTitle(deck: deck, iconSize: nil)
                Spacer(minLength: 0)
                Text(verbatim: deck.status.uppercased())
                    .djFont(.label)
                    .foregroundStyle(deck.isPlaying ? tokens.deck(deck.side) : tokens.tertiary)
                CueButton(deck: deck, width: 42, height: 22)
            }
            GeometryReader { proxy in
                let size = min(proxy.size.width, proxy.size.height)
                Platter(deck: deck, size: size)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            DeckWave(deck: deck, barWidth: 2)
                .frame(height: 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// HI, MID, LOW and FILTER above the channel fader.
private struct ClubStrip: View {
    let deck: DeckControls

    @Environment(\.djTokens) private var tokens
    @Environment(\.panelMetrics) private var metrics

    var body: some View {
        let knob = metrics.knob - 4
        let tint = tokens.deck(deck.side)
        VStack(spacing: 8) {
            Grid(horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    ToneKnob(deck: deck, band: .hi, size: knob, tint: tint)
                    ToneKnob(deck: deck, band: .mid, size: knob, tint: tint)
                }
                GridRow {
                    ToneKnob(deck: deck, band: .low, size: knob, tint: tint)
                    ToneKnob(deck: deck, band: .filter, size: knob, tint: tint)
                }
            }
            DeckFader(deck: deck, tint: tint)
                .frame(width: 40)
                .frame(maxHeight: .infinity)
        }
        .padding(10)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: tokens.cardRadius, style: .continuous).fill(tokens.surface))
        .deckEnabled(deck.isLoaded)
    }
}

/// A turning record at 33⅓ rpm while its app plays. Still with Reduce Motion. A click plays or pauses
/// Music or Spotify when that app is on the deck.
private struct Platter: View {
    let deck: DeckControls
    let size: CGFloat

    @EnvironmentObject private var now: NowPlayingMonitor
    @Environment(\.djTokens) private var tokens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let degreesPerSecond = 360 * (100.0 / 3) / 60

    var body: some View {
        let spinning = deck.isPlaying && !reduceMotion
        let controllable = deck.appID != nil && now.entry?.source.bundleID == deck.appID
            && now.entry?.source.isScriptable == true
        ZStack {
            Circle().fill(Color(hex: 0x0B0B0D))
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !spinning)) { context in
                record
                    .rotationEffect(.degrees(spinning ? angle(at: context.date) : 0))
            }
            Circle()
                .strokeBorder(deck.isPlaying ? tokens.deck(deck.side) : tokens.line, lineWidth: 2)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .onTapGesture {
            if controllable { now.togglePlay() }
        }
        .help(controllable ? Text("Play or pause") : Text(verbatim: deck.name))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Deck \(deck.side.letter)"))
        .accessibilityValue(Text(verbatim: "\(deck.name), \(deck.status)"))
    }

    private var record: some View {
        ZStack {
            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let outer = min(canvasSize.width, canvasSize.height) / 2
                var radius = outer - 6
                while radius > outer * 0.42 {
                    let ring = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                      width: radius * 2, height: radius * 2))
                    context.stroke(ring, with: .color(.white.opacity(0.05)), lineWidth: 1)
                    radius -= 4
                }
                let mark = Path(roundedRect: CGRect(x: center.x - 1.5, y: center.y - outer + 8, width: 3,
                                                    height: outer * 0.18), cornerRadius: 1.5)
                context.fill(mark, with: .color(.white.opacity(0.55)))
            }
            DeckArtwork(deck: deck, size: size * 0.4, radius: size * 0.2)
        }
        .frame(width: size, height: size)
    }

    private func angle(at date: Date) -> Double {
        (date.timeIntervalSinceReferenceDate * Self.degreesPerSecond).truncatingRemainder(dividingBy: 360)
    }
}
