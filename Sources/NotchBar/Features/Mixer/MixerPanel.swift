import SwiftUI

/// One fader per app, side by side, like a small mixing console.
struct MixerPanel: View {
    @ObservedObject var mixer: AppVolumeMixer
    var highlight: String?
    var spotify: SpotifyConnect? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if mixer.needsExplanation {
                explanation
            } else if mixer.permissionDenied {
                denied
            } else {
                HStack {
                    Text("Mixer")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                    Spacer(minLength: 8)
                    sceneMenu
                }
                if mixer.rows.isEmpty {
                    Text("Keine Apps mit Audio")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                } else if visibleStrips.isEmpty {
                    Text("Gerade spielt nichts. Stumme Apps einblenden, um sie trotzdem zu sehen.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                MixerStripRow(mixer: mixer, highlight: highlight, compact: false, spotify: spotify, rows: visibleStrips)
                CrossfaderBar(mixer: mixer)
            }
            if let status = mixer.statusMessage {
                Text(status).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(height: 330, alignment: .top)
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

    private var sceneMenu: some View {
        Menu {
            sceneItems("Focus")
            sceneItems("Call")
        } label: {
            Text("Scenes").font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10).frame(height: 22)
                .background(Capsule().fill(.white.opacity(0.1)))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder private func sceneItems(_ name: String) -> some View {
        Button("Save \(name)") { mixer.saveScene(name) }
        Button("Recall \(name)") { mixer.recallScene(name) }
            .disabled(!mixer.hasScene(name))
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: compact ? 8 : 12) {
                MasterStrip(mixer: mixer, compact: compact)
                Rectangle().fill(.white.opacity(0.14)).frame(width: 1).padding(.vertical, 6)
                ForEach(strips) { row in
                    ChannelStrip(row: row, mixer: mixer, compact: compact, highlighted: row.id == highlight, spotify: spotify)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: compact ? 168 : 188)
    }
}

/// Horizontal blend between two apps. Equal-power, on top of each app's own fader.
private struct CrossfaderBar: View {
    @ObservedObject var mixer: AppVolumeMixer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                slotMenu(isA: true)
                Spacer(minLength: 4)
                Text("Crossfader")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 4)
                slotMenu(isA: false)
            }
            GeometryReader { g in
                let travel = max(g.size.width - 22, 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule()
                        .fill(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.08)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 22 + travel * mixer.crossfade)
                    Circle()
                        .fill(.white)
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .offset(x: travel * mixer.crossfade + 2)
                }
                .contentShape(Capsule())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    mixer.setCrossfade(Double(min(1, max(0, (value.location.x - 11) / travel))))
                })
            }
            .frame(height: 22)
            Toggle("Stumme Apps zeigen", isOn: Binding(get: { mixer.showSilentApps }, set: { mixer.setShowSilent($0) }))
                .font(.system(size: 11, weight: .medium))
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    private func slotMenu(isA: Bool) -> some View {
        let current = isA ? mixer.crossA : mixer.crossB
        let name = mixer.rows.first { $0.id == current }?.name ?? (isA ? "A" : "B")
        return Menu {
            ForEach(mixer.rows) { row in
                Button(row.name) {
                    if isA { mixer.setCrossA(row.id) } else { mixer.setCrossB(row.id) }
                }
            }
        } label: {
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: isA ? .leading : .trailing)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 120)
    }
}

/// The system output. Visually heavier than an app strip, and it never installs a process tap.
struct MasterStrip: View {
    @ObservedObject var mixer: AppVolumeMixer
    var compact: Bool
    /// Home hides the device menu so the pill stays easy to grab.
    var detailed: Bool = true

    var body: some View {
        VStack(spacing: 4) {
            PillFader(level: mixer.master.level, maxLevel: 100, muted: mixer.master.muted, width: compact ? 48 : 56) {
                mixer.setMasterLevel($0)
            } onMute: {
                mixer.toggleMasterMute()
            } onReset: {
                mixer.setMasterLevel(100)
            } icon: {
                Image(systemName: mixer.master.muted ? "speaker.slash.fill" : "speaker.wave.3.fill")
                    .font(.system(size: compact ? 14 : 18, weight: .semibold))
            }
            if detailed {
                Menu {
                    ForEach(mixer.outputDevices()) { device in
                        Button(device.name) { mixer.setSystemOutput(uid: device.uid) }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(mixer.master.name)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(2)
                        Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                    }
                    .frame(width: compact ? 56 : 68, height: 26, alignment: .top)
                }
                .menuStyle(.borderlessButton)
                .frame(width: compact ? 56 : 68)
            } else {
                Text("System")
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .frame(width: compact ? 56 : 68)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.08)))
        .help("System volume. Double-click for 100%.")
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
    @State private var shimmer = false

    private var silenced: Bool { row.muted || (mixer.soloID != nil && mixer.soloID != row.id) }
    @Environment(\.notchChrome) private var chrome
    private var column: CGFloat {
        switch chrome.faderStyle {
        case .line: return compact ? 40 : 44
        case .pill: return 52
        case .tall: return 56
        }
    }

    var body: some View {
        VStack(spacing: 4) {
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
            Text(mixer.soloID == row.id ? "Solo" : row.name)
                .font(.system(size: 10, weight: highlighted || mixer.soloID == row.id ? .semibold : .medium))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .frame(width: column)
            if detailed {
                outputMenu.frame(width: column, height: 14)
            }
            if row.id == SpotifyConnect.spotifyBundle, let spotify, spotify.isEnabled {
                SpotifyDeviceMenu(spotify: spotify)
                    .frame(width: compact ? 64 : 76)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(.white.opacity(highlighted ? 0.55 : 0), lineWidth: 1.5))
        .opacity(row.playing ? 1 : 0.45)
        .help("\(row.name). Double-click for 100%. Option-click to solo. The chevron picks an output.")
    }

    private var outputMenu: some View {
        Menu {
            Button("System Default") { mixer.setAppOutput(row.id, uid: nil) }
            ForEach(mixer.outputDevices()) { device in
                Button(device.name) { mixer.setAppOutput(row.id, uid: device.uid) }
            }
        } label: {
            Text(row.outputLabel ?? "Default")
                .font(.system(size: 9))
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
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
                        .font(chrome.font(11, weight: .semibold))
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
private struct ScrollWheelCatcher: NSViewRepresentable {
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

@MainActor
private enum MixerIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] { return cached }
        guard let icon = MediaSource.forBundle(bundleID).icon else { return nil }
        icon.size = NSSize(width: 32, height: 32)
        cache[bundleID] = icon
        return icon
    }
}
