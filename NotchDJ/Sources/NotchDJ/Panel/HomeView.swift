import AppKit
import SwiftUI

/// The first tab: what is playing, the master volume and output, and the apps making sound.
struct HomeView: View {
    @Environment(\.panelMetrics) private var metrics

    var body: some View {
        HStack(alignment: .top, spacing: metrics.padding) {
            NowPlayingCard()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            MasterCard()
                .frame(width: metrics.masterKnob + 52)
                .frame(maxHeight: .infinity)
            PlayingAppsCard()
                .frame(width: metrics.size == .compact ? 188 : 212)
                .frame(maxHeight: .infinity)
        }
    }
}

// MARK: Now playing

private struct NowPlayingCard: View {
    @EnvironmentObject private var now: NowPlayingMonitor
    @EnvironmentObject private var mixer: AppVolumeMixer
    @EnvironmentObject private var prefs: DJPreferences
    @EnvironmentObject private var permissions: PermissionCenter
    @Environment(\.djTokens) private var tokens
    @Environment(\.panelMetrics) private var metrics
    @Environment(\.heroNamespace) private var hero

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let entry = now.entry {
                track(entry)
            } else if let row = mixer.rows.first(where: \.playing) {
                otherApp(row)
            } else {
                idle
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .djCard(padding: 14)
    }

    private func track(_ entry: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ArtworkView(image: now.artwork, bundleID: entry.source.bundleID, size: metrics.artwork)
                    .hero("artwork", hero)
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(entry.source.appName)
                    Text(entry.title)
                        .djFont(.title)
                        .lineLimit(3)
                    Text(entry.artist)
                        .djFont(.body)
                        .foregroundStyle(tokens.secondary)
                        .lineLimit(2)
                    if !entry.album.isEmpty {
                        Text(entry.album)
                            .djFont(.caption)
                            .foregroundStyle(tokens.tertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if entry.isPlaying {
                        LevelHistory(source: MeterSource(bank: mixer.meters, id: entry.source.bundleID),
                                     tint: tokens.accent, barWidth: 3)
                            .frame(height: 26)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: metrics.artwork, alignment: .topLeading)
            }
            Spacer(minLength: 0)
            if entry.hasTimeline {
                Scrubber(entry: entry)
            }
            TransportButtons(size: 15)
                .frame(maxWidth: .infinity)
        }
    }

    /// An app that can't be scripted is playing. Media keys reach it when that's allowed.
    private func otherApp(_ row: AppVolumeRow) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ArtworkView(image: nil, bundleID: row.id, size: metrics.artwork)
                    .hero("artwork", hero)
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(String(localized: "Playing"))
                    Text(MixerDisplayName.short(bundleID: row.id, fallback: row.name))
                        .djFont(.title)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    LevelHistory(source: MeterSource(bank: mixer.meters, id: row.id), tint: tokens.accent)
                        .frame(height: 26)
                }
                .frame(maxWidth: .infinity, maxHeight: metrics.artwork, alignment: .topLeading)
            }
            Spacer(minLength: 0)
            if prefs.mediaKeys && permissions.accessibility {
                MediaKeyButtons()
                    .frame(maxWidth: .infinity)
            } else {
                Text("Turn on media keys in Settings › Extras to control this app.")
                    .djFont(.caption)
                    .foregroundStyle(tokens.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                ArtworkView(image: nil, bundleID: nil, size: metrics.artwork)
                    .hero("artwork", hero)
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(String(localized: "Now Playing"))
                    Text("Nothing is playing")
                        .djFont(.title)
                    Text("Start Music or Spotify, or any app with sound.")
                        .djFont(.caption)
                        .foregroundStyle(tokens.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ForEach(MediaSource.scriptable, id: \.bundleID) { source in
                    if source.isInstalled {
                        ChipButton(title: source.appName, systemImage: "play.fill") {
                            guard let url = source.appURL else { return }
                            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                        }
                    }
                }
            }
        }
    }
}

/// Play, next and previous as system media keys.
private struct MediaKeyButtons: View {
    @EnvironmentObject private var now: NowPlayingMonitor

    var body: some View {
        HStack(spacing: 18) {
            key("backward.fill", String(localized: "Previous"), .previous)
            key("playpause.fill", String(localized: "Play or Pause"), .toggle)
            key("forward.fill", String(localized: "Next"), .next)
        }
    }

    private func key(_ symbol: String, _ label: String, _ command: PlayerScripts.Command) -> some View {
        Button {
            now.sendMediaKey(command)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 32, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: Master

private struct MasterCard: View {
    @EnvironmentObject private var mixer: AppVolumeMixer
    @Environment(\.djTokens) private var tokens
    @Environment(\.panelMetrics) private var metrics

    var body: some View {
        VStack(spacing: 12) {
            SectionLabel(String(localized: "Master"))
            DJKnob(value: level, label: String(localized: "Volume"), size: metrics.masterKnob,
                   defaultValue: 0.5, bipolar: false, tint: tokens.accent,
                   format: { "\(Int(($0 * 100).rounded()))%" })
                .opacity(mixer.master.muted ? 0.45 : 1)
            Text(verbatim: "\(mixer.master.level)")
                .djFont(.bigValue)
                .foregroundStyle(mixer.master.muted ? tokens.tertiary : tokens.text)
            MeterBar(source: MeterSource(bank: mixer.meters, id: nil), axis: .horizontal, thickness: 5, stereo: true)
                .frame(width: metrics.masterKnob)
            HStack(spacing: 8) {
                PadButton(title: "M", active: mixer.master.muted, tint: tokens.meterHot,
                          help: String(localized: "Mute")) {
                    mixer.toggleMasterMute()
                }
            }
            Spacer(minLength: 0)
            SystemOutputMenu()
                .frame(maxWidth: metrics.masterKnob + 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .djCard(padding: 12)
    }

    private var level: Binding<Double> {
        Binding(get: { Double(mixer.master.level) / 100 },
                set: { mixer.setMasterLevel(Int(($0 * 100).rounded())) })
    }
}

// MARK: Playing apps

private struct PlayingAppsCard: View {
    @EnvironmentObject private var model: DJModel
    @EnvironmentObject private var mixer: AppVolumeMixer
    @Environment(\.djTokens) private var tokens

    var body: some View {
        let playing = mixer.rows.filter(\.playing)
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(String(localized: "Playing apps"))
            if playing.isEmpty {
                Text("Apps appear here while they make sound.")
                    .djFont(.caption)
                    .foregroundStyle(tokens.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(playing) { row in
                            SourceRow(row: row)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ChipButton(title: PanelTab.mixer.title, systemImage: "slider.vertical.3") { model.select(.mixer) }
                ChipButton(title: PanelTab.dj.title, systemImage: "dial.medium") { model.select(.dj) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .djCard(padding: 12)
    }
}

/// Icon, name, mini meter and mute. A click opens that strip in MIXER.
private struct SourceRow: View {
    let row: AppVolumeRow

    @EnvironmentObject private var model: DJModel
    @EnvironmentObject private var mixer: AppVolumeMixer
    @Environment(\.djTokens) private var tokens

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                AppIconView(bundleID: row.id, size: 20)
                VStack(alignment: .leading, spacing: 3) {
                    Text(MixerDisplayName.short(bundleID: row.id, fallback: row.name))
                        .djFont(.caption)
                        .lineLimit(1)
                    MeterBar(source: MeterSource(bank: mixer.meters, id: row.id), axis: .horizontal, thickness: 3)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.showStrip(row.id) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: row.name))
            .accessibilityHint(Text("Shows this app in the mixer"))
            .accessibilityAddTraits(.isButton)
            PadButton(title: "M", active: row.muted, tint: tokens.meterHot, width: 24, height: 20,
                      help: String(localized: "Mute")) {
                mixer.toggleMute(row.id)
            }
        }
        .padding(.vertical, 2)
    }
}
