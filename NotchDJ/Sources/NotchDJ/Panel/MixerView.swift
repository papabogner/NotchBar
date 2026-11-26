import SwiftUI

/// One strip per app, then the master strip pinned on the right.
struct MixerView: View {
    @EnvironmentObject private var model: DJModel
    @EnvironmentObject private var mixer: AppVolumeMixer
    @Environment(\.djTokens) private var tokens

    var body: some View {
        let rows = mixer.showSilentApps ? mixer.rows : mixer.rows.filter(\.playing)
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if rows.isEmpty {
                    empty
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(rows) { row in
                                    ChannelStrip(row: row, highlighted: model.highlightedStrip == row.id)
                                        .id(row.id)
                                }
                            }
                            .padding(.vertical, 1)
                        }
                        .onAppear {
                            if let id = model.highlightedStrip { proxy.scrollTo(id, anchor: .center) }
                        }
                    }
                }
                Rectangle()
                    .fill(tokens.line)
                    .frame(width: tokens.lineWidth)
                    .frame(maxHeight: .infinity)
                MasterStrip()
            }
            .frame(maxHeight: .infinity)
            footer
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "speaker.zzz")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(tokens.tertiary)
            Text("No app is making sound")
                .djFont(.title)
            Text("Play something, or show silent apps below.")
                .djFont(.caption)
                .foregroundStyle(tokens.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Toggle(isOn: Binding(get: { mixer.showSilentApps }, set: { mixer.setShowSilent($0) })) {
                Text("Show silent apps").djFont(.caption)
            }
            .toggleStyle(.checkbox)
            if mixer.showSavedHint {
                Text("Saved levels apply when you move a fader.")
                    .djFont(.caption)
                    .foregroundStyle(tokens.tertiary)
            }
            Spacer()
            Button {
                mixer.resetAll()
            } label: {
                Text("Reset All").djFont(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(tokens.secondary)
            .help(Text("Every app back to normal volume, unmuted, on the system output."))
        }
    }
}

/// Icon and name, value, fader with meter, mute, solo and output.
private struct ChannelStrip: View {
    let row: AppVolumeRow
    let highlighted: Bool

    @EnvironmentObject private var mixer: AppVolumeMixer
    @Environment(\.djTokens) private var tokens
    @Environment(\.panelMetrics) private var metrics

    private var width: CGFloat { metrics.size == .large ? 78 : 70 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: tokens.cardRadius, style: .continuous)
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                AppIconView(bundleID: row.id, size: 24)
                AppOutputMenu(bundleID: row.id)
            }
            Text(MixerDisplayName.short(bundleID: row.id, fallback: row.name))
                .djFont(.caption)
                .lineLimit(1)
                .frame(maxWidth: width - 8)
            Text(verbatim: "\(row.level)")
                .djFont(.value)
                .foregroundStyle(row.muted ? tokens.tertiary : tokens.text)
            DJFader(value: level, label: row.name, defaultValue: DeckControls.unity, detents: [DeckControls.unity],
                    meter: MeterSource(bank: mixer.meters, id: row.id), format: ToneText.level)
                .frame(width: 36)
                .frame(maxHeight: .infinity)
            HStack(spacing: 4) {
                PadButton(title: "M", active: row.muted, tint: tokens.meterHot, width: 26, height: 22,
                          help: String(localized: "Mute")) {
                    mixer.toggleMute(row.id)
                }
                PadButton(title: "S", active: mixer.soloID == row.id, tint: tokens.accent, width: 26, height: 22,
                          help: String(localized: "Solo")) {
                    mixer.toggleSolo(row.id)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(width: width)
        .background {
            switch tokens.card {
            case .filled: shape.fill(tokens.surface)
            case .outlined: shape.strokeBorder(tokens.line, lineWidth: tokens.lineWidth)
            case .plain: Color.clear
            }
        }
        .overlay {
            if highlighted { shape.strokeBorder(tokens.accent, lineWidth: 2) }
        }
        .opacity(row.playing ? 1 : 0.55)
    }

    private var level: Binding<Double> {
        let id = row.id
        return Binding(get: { Double(mixer.row(id)?.level ?? 100) / 150 },
                       set: { mixer.setLevel(id, Int(($0 * 150).rounded())) })
    }
}

/// The system output: volume, mute, stereo meter and device.
private struct MasterStrip: View {
    @EnvironmentObject private var mixer: AppVolumeMixer
    @Environment(\.djTokens) private var tokens

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: mixer.master.symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(height: 24)
            SectionLabel(String(localized: "Master"), color: tokens.secondary)
            Text(verbatim: "\(mixer.master.level)")
                .djFont(.value)
            HStack(spacing: 6) {
                DJFader(value: level, label: String(localized: "Master volume"), defaultValue: 0.5,
                        format: { "\(Int(($0 * 100).rounded()))%" })
                    .frame(width: 36)
                MeterBar(source: MeterSource(bank: mixer.meters, id: nil), thickness: 4, stereo: true)
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 4) {
                PadButton(title: "M", active: mixer.master.muted, tint: tokens.meterHot, width: 26, height: 22,
                          help: String(localized: "Mute")) {
                    mixer.toggleMasterMute()
                }
                SystemOutputMenu(compact: true)
                    .fixedSize()
            }
        }
        .padding(.vertical, 8)
        .frame(width: 96)
    }

    private var level: Binding<Double> {
        Binding(get: { Double(mixer.master.level) / 100 },
                set: { mixer.setMasterLevel(Int(($0 * 100).rounded())) })
    }
}
