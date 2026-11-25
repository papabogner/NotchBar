import SwiftUI

/// One fader per app, side by side, like a small mixing console.
struct MixerPanel: View {
    @ObservedObject var mixer: AppVolumeMixer
    var highlight: String?
    var spotify: SpotifyConnect? = nil
    var nowTitle: String?
    var nowArtist: String?
    var nowBundle: String?
    var artwork: NSImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: MixerLayout.section) {
            if mixer.needsExplanation {
                explanation
            } else if mixer.permissionDenied {
                denied
            } else {
                header
                if mixer.rows.isEmpty {
                    Text("Keine Apps mit Audio")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MixerLayout.secondary)
                } else if mixer.face == .mixer && visibleStrips.isEmpty {
                    Text("Gerade spielt nichts. Stumme Apps einblenden, um sie trotzdem zu sehen.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MixerLayout.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Group {
                    if mixer.face == .dj {
                        DJMixerView(mixer: mixer, nowTitle: nowTitle, nowArtist: nowArtist, nowBundle: nowBundle, artwork: artwork)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    } else {
                        TeenageMixerView(mixer: mixer, highlight: highlight, spotify: spotify)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: mixer.face)
            }
            if let status = mixer.statusMessage {
                Text(status).font(.system(size: 10)).foregroundStyle(MixerLayout.secondary)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(MixerLayout.section)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(TEColor.background)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    private var header: some View {
        HStack(spacing: MixerLayout.section) {
            Text(mixer.face == .dj ? "DJ" : "Mixer")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TEColor.text)
            Spacer(minLength: MixerLayout.section)
            Picker("Style", selection: $mixer.face) {
                ForEach(MixerFace.allCases) { face in
                    Text(face.title).tag(face)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 148)
            .labelsHidden()
            silentToggle
        }
    }

    private var silentToggle: some View {
        Button {
            mixer.setShowSilent(!mixer.showSilentApps)
        } label: {
            Image(systemName: mixer.showSilentApps ? "eye" : "eye.slash")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(mixer.showSilentApps ? 0.92 : 0.55))
                .frame(width: 28, height: 22)
                .background(Capsule().fill(.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .help("Stumme Apps zeigen")
        .accessibilityLabel("Stumme Apps zeigen")
    }

    private var visibleStrips: [AppVolumeRow] {
        mixer.showSilentApps ? mixer.rows : mixer.rows.filter(\.playing)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Adjust each app's volume").font(.system(size: 14, weight: .semibold))
            Text("NotchBar listens to an app only while its fader isn't at 100%, it's muted, or you send it to another speaker. Audio isn't recorded or stored. macOS asks the next time that happens.")
                .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                prominentButton("Continue") { mixer.acceptExplanation() }
                quietButton("Not Now") { mixer.declineExplanation() }
            }
            .padding(.top, 2)
        }
    }

    private var denied: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Audio access is off").font(.system(size: 14, weight: .semibold))
            Text(mixer.statusMessage ?? "Turn on system audio recording for NotchBar in Privacy & Security. Nothing is recorded or stored.")
                .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            prominentButton("Open Settings") { mixer.openPrivacySettings() }
                .padding(.top, 2)
        }
    }

    private func prominentButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.black)
                .padding(.horizontal, 12).frame(height: 26)
                .background(Capsule().fill(.white))
        }
        .buttonStyle(PressableStyle(scale: 0.95))
    }

    private func quietButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11.5, weight: .semibold))
                .padding(.horizontal, 12).frame(height: 26)
                .background(Capsule().fill(.white.opacity(0.1)))
        }
        .buttonStyle(PressableStyle(scale: 0.95))
    }
}

/// Master fader plus one strip per app. The master strip is the system output.
struct MixerStripRow: View {
    @ObservedObject var mixer: AppVolumeMixer
    var highlight: String?
    var compact: Bool
    var spotify: SpotifyConnect? = nil
    /// The strips to draw. Home passes its own short list; the mixer tab passes the visible rows.
    var rows: [AppVolumeRow]? = nil

    private var strips: [AppVolumeRow] {
        if let rows { return rows }
        return mixer.showSilentApps ? mixer.rows : mixer.rows.filter(\.playing)
    }

    var body: some View {
        if compact {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    stripColumns(width: nil)
                }
            }
            .frame(height: 168)
        } else {
            GeometryReader { geo in
                let count = strips.count + 1
                let gap = MixerLayout.section
                let needed = MixerLayout.minStrip * CGFloat(count) + gap * CGFloat(max(count - 1, 0))
                if needed > geo.size.width {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: gap) {
                            stripColumns(width: MixerLayout.minStrip)
                        }
                    }
                } else {
                    let slots = CGFloat(max(count, 1))
                    let gaps = CGFloat(max(count - 1, 0))
                    let capped = MixerLayout.maxStrip * slots + gap * gaps
                    let width = capped <= geo.size.width
                        ? MixerLayout.maxStrip
                        : (geo.size.width - gap * gaps) / slots
                    let spacing = count > 1 && capped <= geo.size.width
                        ? (geo.size.width - MixerLayout.maxStrip * slots) / gaps
                        : gap
                    HStack(alignment: .top, spacing: spacing) {
                        stripColumns(width: width)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: MixerLayout.stripHeight)
        }
    }

    @ViewBuilder private func stripColumns(width: CGFloat?) -> some View {
        MasterStrip(mixer: mixer, compact: compact, stripWidth: width)
        ForEach(strips) { row in
            ChannelStrip(row: row, mixer: mixer, compact: compact, highlighted: row.id == highlight, spotify: spotify, stripWidth: width)
        }
    }
}

enum MixerLayout {
    static let section: CGFloat = 16
    static let minStrip: CGFloat = 72
    static let maxStrip: CGFloat = 84
    static let faderHeight: CGFloat = 136
    static let nameHeight: CGFloat = 28
    static let captionHeight: CGFloat = 14
    static var stripHeight: CGFloat { faderHeight + 8 + nameHeight + 8 + captionHeight }
    static let secondary = Color.white.opacity(0.55)
}

/// The system output. Visually heavier than an app strip, and it never installs a process tap.
struct MasterStrip: View {
    @ObservedObject var mixer: AppVolumeMixer
    var compact: Bool
    /// Home hides the device menu so the pill stays easy to grab.
    var detailed: Bool = true
    var stripWidth: CGFloat? = nil

    private var column: CGFloat { stripWidth ?? (compact ? 48 : MixerLayout.maxStrip) }

    var body: some View {
        VStack(spacing: 8) {
            PillFader(level: mixer.master.level, maxLevel: 100, muted: mixer.master.muted, width: column) {
                mixer.setMasterLevel($0)
            } onMute: {
                mixer.toggleMasterMute()
            } onReset: {
                mixer.setMasterLevel(100)
            } icon: {
                Image(systemName: mixer.master.muted ? "speaker.slash.fill" : "speaker.wave.3.fill")
                    .font(.system(size: compact ? 14 : 16, weight: .semibold))
            }
            .frame(height: compact ? 120 : MixerLayout.faderHeight)
            Text("Mac")
                .font(.system(size: 11, weight: .medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: column, height: compact ? 14 : MixerLayout.nameHeight, alignment: .top)
            if detailed {
                deviceMenu
            }
        }
        .frame(width: column)
        .help("System volume. Double-click for 100%. The caption picks the output.")
    }

    private var deviceMenu: some View {
        Menu {
            ForEach(mixer.outputDevices()) { device in
                Button(device.name) { mixer.setSystemOutput(uid: device.uid) }
            }
        } label: {
            Text(mixer.master.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MixerLayout.secondary)
                .lineLimit(1)
                .frame(width: column, height: MixerLayout.captionHeight)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: column, height: MixerLayout.captionHeight)
    }
}

/// A vertical channel: icon, name, fader, level, mute.
struct ChannelStrip: View {
    let row: AppVolumeRow
    @ObservedObject var mixer: AppVolumeMixer
    var compact: Bool
    var highlighted: Bool
    var detailed: Bool = true
    var spotify: SpotifyConnect? = nil
    var stripWidth: CGFloat? = nil
    @State private var shimmer = false

    private var silenced: Bool { row.muted || (mixer.soloID != nil && mixer.soloID != row.id) }
    private var column: CGFloat { stripWidth ?? (compact ? 48 : MixerLayout.maxStrip) }
    private var displayName: String {
        mixer.soloID == row.id ? "Solo" : MixerDisplayName.short(bundleID: row.id, fallback: row.name)
    }

    var body: some View {
        VStack(spacing: 8) {
            PillFader(level: silenced ? 0 : row.level, maxLevel: 150, muted: silenced, width: column) {
                mixer.setLevel(row.id, $0)
            } onMute: {
                mixer.toggleMute(row.id)
            } onReset: {
                mixer.setLevel(row.id, 100)
            } onSolo: {
                mixer.toggleSolo(row.id)
            } icon: {
                icon
            }
            .frame(height: compact ? 120 : MixerLayout.faderHeight)
            Text(displayName)
                .font(.system(size: 11, weight: .medium))
                .multilineTextAlignment(.center)
                .lineLimit(compact ? 1 : 2)
                .frame(width: column, height: compact ? 14 : MixerLayout.nameHeight, alignment: .top)
            if detailed {
                outputMenu
            }
            if row.id == SpotifyConnect.spotifyBundle, let spotify, spotify.isEnabled {
                SpotifyDeviceMenu(spotify: spotify)
                    .frame(width: column)
            }
        }
        .frame(width: column)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.white.opacity(highlighted ? 0.08 : 0)))
        .opacity(row.playing ? 1 : 0.45)
        .help("\(row.name). Double-click for 100%. Option-click to solo. The caption picks an output.")
    }

    private var outputMenu: some View {
        Menu {
            Button("System Default") { mixer.setAppOutput(row.id, uid: nil) }
            ForEach(mixer.outputDevices()) { device in
                Button(device.name) { mixer.setAppOutput(row.id, uid: device.uid) }
            }
        } label: {
            Text(row.outputLabel ?? "Default")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MixerLayout.secondary)
                .lineLimit(1)
                .frame(width: column, height: MixerLayout.captionHeight)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: column, height: MixerLayout.captionHeight)
    }

    @ViewBuilder private var icon: some View {
        let side: CGFloat = compact ? 16 : 26
        ZStack(alignment: .topTrailing) {
            if let image = MixerIcons.icon(for: row.id) {
                Image(nsImage: image).resizable().frame(width: side, height: side)
            } else {
                Image(systemName: "app.fill").font(.system(size: compact ? 11 : 14)).frame(width: side, height: side)
            }
            if row.playing {
                Circle().fill(Color.green).frame(width: 7, height: 7)
                    .opacity(shimmer ? 1 : 0.4)
                    .offset(x: 3, y: -3)
                    .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { shimmer = true } }
            }
        }
    }
}

/// A tall rounded pill. Drag moves from where you grabbed, scroll changes a step,
/// double-click returns to 100%, and the icon mutes.
private struct PillFader<Icon: View>: View {
    var level: Int
    var maxLevel: Int
    var muted: Bool
    var width: CGFloat
    var onChange: (Int) -> Void
    var onMute: () -> Void
    var onReset: () -> Void
    var onSolo: (() -> Void)? = nil
    @ViewBuilder var icon: Icon
    @Environment(\.notchChrome) private var chrome
    @State private var dragging = false
    @State private var origin: Int?

    var body: some View {
        let wide = chrome.faderStyle != .line
        let track: CGFloat = chrome.faderStyle == .line ? 4 : (chrome.faderStyle == .tall ? 36 : 32)
        let corner = track / 2
        return GeometryReader { g in
            let fraction = CGFloat(min(maxLevel, max(0, level))) / CGFloat(max(maxLevel, 1))
            let fill = muted ? 0 : g.size.height * fraction
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(.white.opacity(wide ? 0.12 : 0.16))
                    .frame(width: track, height: g.size.height)
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(chrome.accent.opacity(muted ? 0.28 : 0.92))
                    .frame(width: track, height: max(wide ? 10 : track, fill))
                    .shadow(color: chrome.accent.opacity(muted || !wide ? 0 : 0.38), radius: wide ? 8 : 0)
                if wide {
                    Circle().fill(.white.opacity(0.95))
                        .frame(width: 8, height: 8)
                        .shadow(color: .black.opacity(0.28), radius: 1, y: 1)
                        .offset(y: -max(2, fill - 6))
                }
                VStack(spacing: 0) {
                    Text(muted ? "Off" : "\(level)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    Button(action: onMute) {
                        icon.foregroundStyle(.white.opacity(0.9))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.9))
                }
            }
            .frame(width: wide ? track : max(width * 0.55, 28), height: g.size.height)
            .frame(maxWidth: .infinity)
            .scaleEffect(dragging ? 1.04 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: dragging)
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: level)
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: muted)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .gesture(DragGesture(minimumDistance: 4).onChanged { value in
                if origin == nil {
                    origin = level
                    dragging = true
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
                let travel = max(g.size.height, 1)
                let delta = Int((-value.translation.height / travel * CGFloat(maxLevel)).rounded())
                onChange(min(maxLevel, max(0, (origin ?? level) + delta)))
            }.onEnded { _ in
                origin = nil
                dragging = false
            })
            .onTapGesture(count: 2) { onReset() }
            .simultaneousGesture(TapGesture().modifiers(.option).onEnded { onSolo?() })
            .background(ScrollWheelCatcher { delta in
                let step = max(1, Int((abs(delta) / 12).rounded()))
                let next = level + (delta > 0 ? step : -step)
                onChange(min(maxLevel, max(0, next)))
            })
            .accessibilityLabel("Volume")
        }
        .frame(maxHeight: .infinity)
        .frame(width: wide ? max(width, track + 8) : (width + 8) * chrome.faderWidthScale)
    }
}

/// Trackpad and mouse-wheel changes, delivered on the main thread by AppKit.
struct ScrollWheelCatcher: NSViewRepresentable {
    var onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> WheelView {
        let view = WheelView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: WheelView, context: Context) {
        view.onScroll = onScroll
    }

    final class WheelView: NSView {
        var onScroll: ((CGFloat) -> Void)?
        override func scrollWheel(with event: NSEvent) {
            let delta = event.scrollingDeltaY
            guard delta != 0 else { return }
            onScroll?(delta)
        }
    }
}

enum MixerDisplayName {
    static func short(bundleID: String, fallback: String) -> String {
        if let known = known[bundleID] { return known }
        var name = fallback
        for prefix in ["Google ", "Mozilla ", "Apple "] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }
        let helper = " Helper"
        if name.hasSuffix(helper) { name.removeLast(helper.count) }
        return name
    }

    private static let known: [String: String] = [
        "com.google.Chrome": "Chrome",
        "com.google.Chrome.beta": "Chrome",
        "com.apple.Safari": "Safari",
        "com.apple.SafariTechnologyPreview": "Safari",
        "com.spotify.client": "Spotify",
        "com.apple.Music": "Music",
        "com.apple.finder": "Finder",
        "com.microsoft.edgemac": "Edge",
        "com.brave.Browser": "Brave",
        "company.thebrowser.Browser": "Arc",
        "com.apple.dt.Xcode": "Xcode",
        "com.apple.Terminal": "Terminal",
        "com.apple.FaceTime": "FaceTime",
        "us.zoom.xos": "Zoom",
        "com.microsoft.teams": "Teams",
        "com.microsoft.teams2": "Teams",
        "com.cisco.webexmeetingsapp": "Webex",
        "com.apple.podcasts": "Podcasts",
        "com.apple.TV": "TV",
        "com.apple.QuickTimePlayerX": "QuickTime",
        "com.apple.mail": "Mail",
        "org.mozilla.firefox": "Firefox",
        "com.tinyspeck.slackmacgap": "Slack",
        "com.hnc.Discord": "Discord",
        "com.openai.chat": "ChatGPT",
        "com.anthropic.claudefordesktop": "Claude",
        "com.todesktop.230313mzl4w4u92": "Cursor",
    ]
}

@MainActor
enum MixerIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] { return cached }
        guard let icon = MediaSource.forBundle(bundleID).icon else { return nil }
        icon.size = NSSize(width: 32, height: 32)
        cache[bundleID] = icon
        return icon
    }
}
