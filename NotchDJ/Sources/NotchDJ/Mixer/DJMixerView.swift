// Based on NotchBar (https://github.com/srisanthosh/NotchBar), GPLv3.
// Original copyright remains with the NotchBar authors. Notch DJ changes are under the same license.
import AppKit
import SwiftUI

/// Two decks. EQ, filter and gain run in the tap, on the render thread.
struct DJMixerView: View {
    @ObservedObject var mixer: AppVolumeMixer
    var nowTitle: String?
    var nowArtist: String?
    var nowBundle: String?
    var artwork: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: MixerLayout.section) {
            HStack(alignment: .top, spacing: MixerLayout.section) {
                deck(isA: true)
                deck(isA: false)
            }
            TECrossfader(mixer: mixer, tint: TEColor.text)
            CurvePills(mixer: mixer)
        }
    }

    private func deck(isA: Bool) -> some View {
        let id = isA ? mixer.crossA : mixer.crossB
        let row = mixer.rows.first { $0.id == id }
        let tone = isA ? mixer.toneA : mixer.toneB
        let tint = isA ? TEColor.deckA : TEColor.deckB
        let playingHere = id != nil && id == nowBundle
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                art(bundleID: id, useArtwork: playingHere)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isA ? "A" : "B")
                        .font(.system(size: 9, weight: .medium))
                        .tracking(0.5)
                        .foregroundStyle(tint)
                    Text(title(row: row, playingHere: playingHere))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TEColor.text)
                        .lineLimit(2)
                    if playingHere, let nowArtist, !nowArtist.isEmpty {
                        Text(nowArtist)
                            .font(.system(size: 10))
                            .foregroundStyle(TEColor.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                toneKnob("HI", tone.hi, .white) { set(isA, tone, hi: $0) }
                toneKnob("MID", tone.mid, TEColor.secondary) { set(isA, tone, mid: $0) }
                toneKnob("LOW", tone.low, TEColor.text, filled: true) { set(isA, tone, low: $0) }
                toneKnob("FILTER", tone.filter, tint) { set(isA, tone, filter: $0) }
                toneKnob("GAIN", tone.gain, tint) { set(isA, tone, gain: $0) }
            }
            HStack(alignment: .center, spacing: 8) {
                SegmentMeter(peak: id.flatMap { mixer.deckMeters[$0]?.peak } ?? 0,
                             rms: id.flatMap { mixer.deckMeters[$0]?.rms } ?? 0,
                             tint: tint, dim: row?.playing != true)
                Spacer(minLength: 0)
                TESquareButton(title: "CUE", active: id != nil && mixer.soloID == id, tint: tint, width: 36) {
                    guard let id else { return }
                    mixer.toggleSolo(id)
                }
            }
            if let row {
                TEFader(level: row.muted ? 0 : row.level, maxLevel: 150, muted: row.muted, tint: tint) {
                    mixer.setLevel(row.id, $0)
                }
                .frame(height: 96)
                TEValue(text: row.muted ? "OFF" : "\(row.level)")
            } else {
                TEMicroLabel(text: "Pick a deck")
                    .frame(height: 96)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(tint.opacity(0.45), lineWidth: 1))
    }

    private func title(row: AppVolumeRow?, playingHere: Bool) -> String {
        if playingHere, let nowTitle, !nowTitle.isEmpty { return nowTitle }
        guard let row else { return "—" }
        return MixerDisplayName.short(bundleID: row.id, fallback: row.name)
    }

    @ViewBuilder private func art(bundleID: String?, useArtwork: Bool) -> some View {
        if useArtwork, let artwork {
            Image(nsImage: artwork).resizable().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 4))
        } else if let bundleID, let image = MixerIcons.icon(for: bundleID) {
            Image(nsImage: image).resizable().frame(width: 44, height: 44)
        } else {
            RoundedRectangle(cornerRadius: 4).fill(TEColor.panel).frame(width: 44, height: 44)
        }
    }

    private func toneKnob(_ name: String, _ value: Double, _ tint: Color, filled: Bool = false, _ change: @escaping (Double) -> Void) -> some View {
        VStack(spacing: 4) {
            FlatKnob(value: value, tint: tint, diameter: 32, enabled: true, filled: filled, onChange: change)
            TEMicroLabel(text: name)
        }
    }

    private func set(_ isA: Bool, _ tone: DeckTone, hi: Double? = nil, mid: Double? = nil, low: Double? = nil, filter: Double? = nil, gain: Double? = nil) {
        var next = tone
        if let hi { next.hi = hi }
        if let mid { next.mid = mid }
        if let low { next.low = low }
        if let filter { next.filter = filter }
        if let gain { next.gain = gain }
        if isA { mixer.toneA = next } else { mixer.toneB = next }
    }
}
