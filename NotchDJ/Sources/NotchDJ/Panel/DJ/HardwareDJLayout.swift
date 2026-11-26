import SwiftUI

/// A club mixer: channel columns with trim, EQ and filter, LED meters, a master section and the crossfader.
struct HardwareDJLayout: View {
    @EnvironmentObject private var mixer: AppVolumeMixer
    @Environment(\.djTokens) private var tokens

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                HardwareChannel(deck: DeckControls(mixer: mixer, side: .a))
                HardwareMaster()
                    .frame(maxWidth: .infinity)
                HardwareChannel(deck: DeckControls(mixer: mixer, side: .b))
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 16) {
                DeckCrossfader(height: 36)
                CurvePicker(width: 50)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: tokens.cardRadius, style: .continuous).fill(tokens.surface))
        }
    }
}

private struct HardwareChannel: View {
    let deck: DeckControls

    @Environment(\.djTokens) private var tokens
    @Environment(\.panelMetrics) private var metrics

    var body: some View {
        let knob = min(metrics.knob, 48)
        VStack(spacing: 10) {
            DeckTitle(deck: deck, iconSize: 16)
            HStack(alignment: .top, spacing: 12) {
                Grid(horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        ToneKnob(deck: deck, band: .gain, size: knob)
                        ToneKnob(deck: deck, band: .filter, size: knob)
                    }
                    GridRow {
                        ToneKnob(deck: deck, band: .hi, size: knob)
                        ToneKnob(deck: deck, band: .mid, size: knob)
                    }
                    GridRow {
                        ToneKnob(deck: deck, band: .low, size: knob)
                        CueButton(deck: deck, width: knob, height: 26)
                            .frame(height: knob)
                    }
                }
                if let meter = deck.meter {
                    MeterBar(source: meter, thickness: 5, stereo: true)
                        .frame(maxHeight: .infinity)
                }
                DeckFader(deck: deck, showsMeter: false)
                    .frame(width: 38)
                    .frame(maxHeight: .infinity)
            }
            .deckEnabled(deck.isLoaded)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: tokens.cardRadius, style: .continuous).fill(tokens.surface))
    }
}

/// The master LED meter and level, between the channels.
private struct HardwareMaster: View {
    @EnvironmentObject private var mixer: AppVolumeMixer
    @Environment(\.djTokens) private var tokens

    var body: some View {
        VStack(spacing: 8) {
            SectionLabel(String(localized: "Master"), color: tokens.secondary)
            HStack(alignment: .bottom, spacing: 10) {
                MeterScaleMarks()
                MeterBar(source: MeterSource(bank: mixer.meters, id: nil), thickness: 8, stereo: true)
            }
            .frame(maxHeight: .infinity)
            Text(verbatim: "\(mixer.master.level)")
                .djFont(.bigValue)
                .foregroundStyle(mixer.master.muted ? tokens.tertiary : tokens.accent)
            HStack(spacing: 6) {
                PadButton(title: "M", active: mixer.master.muted, tint: tokens.meterHot, width: 28, height: 22,
                          help: String(localized: "Mute")) {
                    mixer.toggleMasterMute()
                }
                SystemOutputMenu(compact: true)
                    .fixedSize()
            }
        }
        .padding(.vertical, 12)
    }
}

/// dB marks beside the master meter: 0, −6, −12, −24, −48 on the 60 dB scale.
private struct MeterScaleMarks: View {
    @Environment(\.djTokens) private var tokens

    var body: some View {
        GeometryReader { proxy in
            ForEach([0, -6, -12, -24, -48], id: \.self) { db in
                let fraction = 1 - CGFloat(db) / CGFloat(MeterScale.floorDB)
                Text(verbatim: db == 0 ? "0" : "\(db)")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(tokens.tertiary)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * (1 - fraction))
            }
        }
        .frame(width: 20)
        .accessibilityHidden(true)
    }
}
