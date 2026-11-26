import SwiftUI

/// Two deck cards side by side and the crossfader below. The default template.
struct StudioDJLayout: View {
    @EnvironmentObject private var mixer: AppVolumeMixer

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StudioDeck(deck: DeckControls(mixer: mixer, side: .a))
                StudioDeck(deck: DeckControls(mixer: mixer, side: .b))
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 16) {
                DeckCrossfader(height: 34)
                CurvePicker()
            }
        }
    }
}

private struct StudioDeck: View {
    let deck: DeckControls

    @Environment(\.djTokens) private var tokens
    @Environment(\.panelMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                DeckArtwork(deck: deck, size: 42, radius: tokens.controlRadius + 2)
                VStack(alignment: .leading, spacing: 2) {
                    DeckTitle(deck: deck, iconSize: nil)
                    Text(verbatim: deck.status)
                        .djFont(.caption)
                        .foregroundStyle(tokens.tertiary)
                }
                Spacer(minLength: 0)
                CueButton(deck: deck)
            }
            if deck.isLoaded {
                DeckWave(deck: deck)
                    .frame(minHeight: 30, maxHeight: .infinity)
                HStack(spacing: 0) {
                    ForEach([ToneBand.hi, .mid, .low, .filter, .gain]) { band in
                        ToneKnob(deck: deck, band: band, size: metrics.knob, tint: tokens.deck(deck.side))
                            .frame(maxWidth: .infinity)
                    }
                }
                HStack(spacing: 10) {
                    SectionLabel(String(localized: "VOL"))
                    DeckFader(deck: deck, axis: .horizontal, tint: tokens.deck(deck.side))
                        .frame(height: 26)
                    Text(verbatim: "\(deck.row?.level ?? 100)")
                        .djFont(.value)
                        .frame(width: 30, alignment: .trailing)
                }
            } else {
                EmptyDeck(side: deck.side)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .djCard(padding: 14)
    }
}
