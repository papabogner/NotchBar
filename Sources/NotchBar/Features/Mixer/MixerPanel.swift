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
                    if mixer.rows.isEmpty {
                        Text("No apps with audio").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                    } else if mixer.showSavedHint || mixer.needsApplyHint {
                        Text("Drag a fader to apply. Option-click solos. Double-click is 100%.")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    sceneMenu
                }
                MixerStripRow(mixer: mixer, highlight: highlight, compact: false)
            }
            if let status = mixer.statusMessage {
                Text(status).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(height: 250, alignment: .top)
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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: compact ? 8 : 10) {
                MasterStrip(mixer: mixer, compact: compact)
                Rectangle().fill(.white.opacity(0.14)).frame(width: 1).padding(.vertical, 6)
                ForEach(mixer.rows) { row in
                    ChannelStrip(row: row, mixer: mixer, compact: compact, highlighted: row.id == highlight, spotify: spotify)
                }
            }
        }
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

    var body: some View {
        VStack(spacing: 4) {
            PillFader(level: silenced ? 0 : row.level, maxLevel: 150, muted: silenced, width: compact ? 48 : 56) {
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
                .frame(width: compact ? 56 : 68)
            if detailed {
                outputMenu.frame(width: compact ? 56 : 68, height: 14)
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
        GeometryReader { g in
            let fraction = CGFloat(min(maxLevel, max(0, level))) / CGFloat(max(maxLevel, 1))
            let fill = muted ? 0 : g.size.height * fraction
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: chrome.faderCorner, style: .continuous).fill(.white.opacity(0.14))
                RoundedRectangle(cornerRadius: chrome.faderCorner, style: .continuous)
                    .fill((chrome.preset == .neon ? chrome.accent : .white).opacity(muted ? 0.28 : 0.92))
                    .frame(height: max(0, fill))
                VStack(spacing: 0) {
                    Text(muted ? "Off" : "\(level)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(muted || fraction < 0.72 ? .white : .black)
                        .padding(.top, 8)
                    Spacer(minLength: 0)
                    Button(action: onMute) {
                        icon.foregroundStyle(muted || fraction < 0.22 ? .white.opacity(0.9) : .black.opacity(0.85))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.9))
                    .padding(.bottom, 8)
                }
            }
            .frame(width: width, height: g.size.height)
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
        .frame(width: width + 8)
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
