import SwiftUI

/// One deck: artwork, a big volume fader and the filter.
struct MinimalDJLayout: View {
    @EnvironmentObject private var mixer: AppVolumeMixer
    @EnvironmentObject private var now: NowPlayingMonitor
    @Environment(\.djTokens) private var tokens
    @Environment(\.panelMetrics) private var metrics

    var body: some View {
        let deck = DeckControls(mixer: mixer, side: .a)
        let track = deck.appID != nil && now.entry?.source.bundleID == deck.appID ? now.entry : nil
        HStack(alignment: .center, spacing: 28) {
            DeckArtwork(deck: deck, size: metrics.artwork + 40)
            VStack(alignment: .leading, spacing: 14) {
                DeckTitle(deck: deck, iconSize: 18, showsLetter: false)
                if let track {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: track.title)
                            .djFont(.display)
                            .lineLimit(2)
                        Text(verbatim: track.artist)
                            .djFont(.body)
                            .foregroundStyle(tokens.secondary)
                            .lineLimit(1)
                    }
                }
                if deck.isLoaded {
                    DeckWave(deck: deck)
                        .frame(height: 44)
                    HStack(alignment: .center, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                SectionLabel(String(localized: "Volume"))
                                Spacer()
                                Text(verbatim: "\(deck.row?.level ?? 100)")
                                    .djFont(.value)
                            }
                            DeckFader(deck: deck, axis: .horizontal)
                                .frame(height: 34)
                        }
                        ToneKnob(deck: deck, band: .filter, size: max(64, metrics.knob + 16))
                    }
                } else {
                    EmptyDeck(side: .a)
                        .frame(height: 120)
                }
                if abs(mixer.crossfade - 0.5) > 0.01 {
                    HStack(spacing: 8) {
                        Text("The crossfader is off center, so this app may be quieter.")
                            .djFont(.caption)
                            .foregroundStyle(tokens.tertiary)
                        ChipButton(title: String(localized: "Center")) { mixer.setCrossfade(0.5) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
