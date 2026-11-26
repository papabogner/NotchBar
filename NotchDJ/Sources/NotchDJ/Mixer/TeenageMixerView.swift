// Based on NotchBar (https://github.com/srisanthosh/NotchBar), GPLv3.
// Original copyright remains with the NotchBar authors. Notch DJ changes are under the same license.
import SwiftUI

/// Teenage Engineering grid, drawn as flat macOS controls. No glass and no fake depth.
struct TeenageMixerView: View {
    @ObservedObject var mixer: AppVolumeMixer
    var highlight: String?

    private var strips: [AppVolumeRow] {
        mixer.showSilentApps ? mixer.rows : mixer.rows.filter(\.playing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MixerLayout.section) {
            GeometryReader { geo in
                let count = strips.count + 1
                let gap = MixerLayout.section
                let needed = MixerLayout.minStrip * CGFloat(count) + gap * CGFloat(max(count - 1, 0))
                if needed > geo.size.width {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: gap) {
                            columns(width: MixerLayout.minStrip)
                        }
                    }
                } else {
                    let slots = CGFloat(max(count, 1))
                    let gaps = CGFloat(max(count - 1, 0))
                    let capped = MixerLayout.maxStrip * slots + gap * gaps
                    let width = capped <= geo.size.width ? MixerLayout.maxStrip : (geo.size.width - gap * gaps) / slots
                    let spacing = count > 1 && capped <= geo.size.width
                        ? (geo.size.width - MixerLayout.maxStrip * slots) / gaps
                        : gap
                    HStack(alignment: .top, spacing: spacing) {
                        columns(width: width)
                    }
                }
            }
            .frame(height: 248)
            TECrossfader(mixer: mixer)
            CurvePills(mixer: mixer)
        }
    }

    @ViewBuilder private func columns(width: CGFloat) -> some View {
        ForEach(strips) { row in
            TEChannel(row: row, mixer: mixer, width: width, highlighted: row.id == highlight)
        }
        TEMaster(mixer: mixer, width: max(width, 72))
    }
}

private struct TEChannel: View {
    let row: AppVolumeRow
    @ObservedObject var mixer: AppVolumeMixer
    var width: CGFloat
    var highlighted: Bool

    private var silenced: Bool { row.muted || (mixer.soloID != nil && mixer.soloID != row.id) }
    private var shown: Int { silenced ? 0 : row.level }

    var body: some View {
        VStack(spacing: 8) {
            icon
            Text(mixer.soloID == row.id ? "Solo" : MixerDisplayName.short(bundleID: row.id, fallback: row.name))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(TEColor.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 28, alignment: .top)
            TEValue(text: row.muted ? "OFF" : "\(shown)")
            HStack(spacing: 4) {
                SegmentMeter(peak: mixer.deckMeters[row.id]?.peak ?? 0, rms: mixer.deckMeters[row.id]?.rms ?? 0,
                             tint: TEColor.accent, dim: !row.playing)
                    .frame(height: 112)
                TEFader(level: shown, maxLevel: 150, muted: row.muted) { mixer.setLevel(row.id, $0) }
                    .frame(height: 112)
            }
            HStack(spacing: 8) {
                TESquareButton(title: "M", active: row.muted) { mixer.toggleMute(row.id) }
                TESquareButton(title: "S", active: mixer.soloID == row.id) { mixer.toggleSolo(row.id) }
            }
        }
        .frame(width: width)
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(highlighted ? Color.white.opacity(0.06) : .clear))
        .opacity(row.playing ? 1 : 0.45)
    }

    @ViewBuilder private var icon: some View {
        if let image = MixerIcons.icon(for: row.id) {
            Image(nsImage: image).resizable().frame(width: 22, height: 22)
        } else {
            RoundedRectangle(cornerRadius: 4).fill(TEColor.panel).frame(width: 22, height: 22)
        }
    }
}

private struct TEMaster: View {
    @ObservedObject var mixer: AppVolumeMixer
    var width: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            TEMicroLabel(text: "Mac")
            FlatKnob(value: Double(mixer.master.level) / 100, tint: TEColor.accent, diameter: min(68, max(56, width)), meter: mixer.masterPeak) { next in
                mixer.setMasterLevel(Int((next * 100).rounded()))
            }
            TEValue(text: mixer.master.muted ? "OFF" : "\(mixer.master.level)")
            TESquareButton(title: "M", active: mixer.master.muted) { mixer.toggleMasterMute() }
            Menu {
                ForEach(mixer.outputDevices()) { device in
                    Button(device.name) { mixer.setSystemOutput(uid: device.uid) }
                }
            } label: {
                Text(mixer.master.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(TEColor.secondary)
                    .lineLimit(1)
                    .frame(width: width)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: width)
        }
        .frame(width: width)
    }
}
