import SwiftUI

/// Line art on paper or black: a display and six knobs per deck, square pads, a hairline crossfader.
struct KODJLayout: View {
    @EnvironmentObject private var mixer: AppVolumeMixer

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            KODeck(deck: DeckControls(mixer: mixer, side: .a))
            KOCenter()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            KODeck(deck: DeckControls(mixer: mixer, side: .b))
        }
    }
}

private struct KODeck: View {
    let deck: DeckControls

    @Environment(\.djTokens) private var tokens
    @Environment(\.panelMetrics) private var metrics

    var body: some View {
        let knob = metrics.knob
        VStack(alignment: .leading, spacing: 12) {
            KODisplay(deck: deck)
            Grid(horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    ToneKnob(deck: deck, band: .hi, size: knob)
                    ToneKnob(deck: deck, band: .mid, size: knob)
                    ToneKnob(deck: deck, band: .low, size: knob)
                }
                GridRow {
                    ToneKnob(deck: deck, band: .filter, size: knob)
                    ToneKnob(deck: deck, band: .gain, size: knob)
                    DJKnob(value: deck.level, label: String(localized: "VOL"), size: knob,
                           defaultValue: DeckControls.unity, bipolar: false, format: ToneText.level)
                }
            }
            .deckEnabled(deck.isLoaded)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                CueButton(deck: deck, width: 44, height: 30)
                DeckSourceMenu(side: deck.side) {
                    Text("LOAD")
                        .djFont(.label)
                        .foregroundStyle(tokens.secondary)
                        .frame(width: 52, height: 30)
                        .overlay(RoundedRectangle(cornerRadius: tokens.controlRadius)
                            .strokeBorder(tokens.line, lineWidth: tokens.lineWidth))
                        .contentShape(Rectangle())
                }
                .help(Text("Choose the app on this deck"))
                Spacer(minLength: 0)
            }
        }
        .frame(width: knob * 3 + 28)
        .frame(maxHeight: .infinity, alignment: .top)
        .djCard(padding: 12)
    }
}

/// A small LCD: deck letter, app, level and a segment meter.
private struct KODisplay: View {
    let deck: DeckControls

    @Environment(\.djTokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(verbatim: deck.side.letter)
                    .djFont(.label)
                    .foregroundStyle(tokens.deck(deck.side))
                Text(verbatim: deck.name.uppercased())
                    .djFont(.label)
                    .foregroundStyle(tokens.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(verbatim: deck.status.uppercased())
                    .djFont(.label)
                    .foregroundStyle(tokens.tertiary)
                    .lineLimit(1)
            }
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(verbatim: String(format: "%03ld", deck.row?.level ?? 0))
                    .djFont(.bigValue)
                    .foregroundStyle(deck.isLoaded ? tokens.text : tokens.tertiary)
                if let meter = deck.meter {
                    MeterBar(source: meter, axis: .horizontal, thickness: 6, stereo: true, look: .segments)
                } else {
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: tokens.controlRadius).fill(tokens.raised))
        .overlay(RoundedRectangle(cornerRadius: tokens.controlRadius)
            .strokeBorder(tokens.line, lineWidth: tokens.lineWidth))
    }
}

/// Master display, curve pads and the crossfader.
private struct KOCenter: View {
    @EnvironmentObject private var mixer: AppVolumeMixer
    @Environment(\.djTokens) private var tokens

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel(String(localized: "Master"), color: tokens.text)
                    Spacer()
                    Text(verbatim: mixer.master.name.uppercased())
                        .djFont(.label)
                        .foregroundStyle(tokens.tertiary)
                        .lineLimit(1)
                }
                Text(verbatim: String(format: "%03ld", mixer.master.level))
                    .djFont(.bigValue)
                MeterBar(source: MeterSource(bank: mixer.meters, id: nil), axis: .horizontal, thickness: 6,
                         stereo: true, look: .segments)
                LevelHistory(source: MeterSource(bank: mixer.meters, id: nil), tint: tokens.accent, barWidth: 2)
                    .frame(maxHeight: .infinity)
            }
            .padding(10)
            .frame(maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: tokens.controlRadius)
                .strokeBorder(tokens.line, lineWidth: tokens.lineWidth))
            CurvePicker(width: 58)
            DeckCrossfader(height: 30)
        }
    }
}
