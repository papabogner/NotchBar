import SwiftUI

/// One fader per app, side by side, like a small mixing console.
struct MixerPanel: View {
    @ObservedObject var mixer: AppVolumeMixer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if mixer.needsExplanation {
                explanation
            } else if mixer.permissionDenied {
                denied
            } else if mixer.rows.isEmpty {
                empty
            } else {
                if mixer.showSavedHint || mixer.needsApplyHint {
                    Text("Move a fader to apply saved levels.")
                        .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5))
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(mixer.rows) { ChannelStrip(row: $0, mixer: mixer, compact: false) }
                    }
                }
            }
            if let status = mixer.statusMessage {
                Text(status).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(height: 184, alignment: .top)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nothing is playing").font(.system(size: 14, weight: .semibold))
            Text("Apps show up here while they make sound.")
                .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5))
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Adjust each app's volume").font(.system(size: 14, weight: .semibold))
            Text("NotchBar listens to an app only while its fader isn't at 100%, then plays it at that level. Audio isn't recorded or stored. macOS asks the next time you move a fader.")
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

/// Mini faders on Home. Hidden by the caller when nothing is playing.
struct HomeMixerWidget: View {
    @ObservedObject var mixer: AppVolumeMixer
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: "Mixer", action: open) { Image(systemName: "slider.horizontal.3") }
            if mixer.needsApplyHint {
                Text("Drag a fader to apply.").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(mixer.rows) { ChannelStrip(row: $0, mixer: mixer, compact: true) }
                }
            }
            .frame(height: mixer.needsApplyHint ? 78 : 92)
        }
    }
}

/// A vertical channel: icon, name, fader, level, mute.
private struct ChannelStrip: View {
    let row: AppVolumeRow
    @ObservedObject var mixer: AppVolumeMixer
    var compact: Bool

    var body: some View {
        VStack(spacing: compact ? 3 : 5) {
            icon
            Text(row.name)
                .font(.system(size: compact ? 9 : 10.5, weight: .medium))
                .lineLimit(1)
                .frame(width: compact ? 48 : 64)
            VolumeFader(level: row.muted ? 0 : row.level, enabled: !row.muted) { mixer.setLevel(row.id, $0) }
                .frame(maxHeight: compact ? 36 : .infinity)
                .accessibilityLabel("\(row.name) volume")
            Text(row.muted ? "Off" : "\(row.level)")
                .font(.system(size: compact ? 9 : 11, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
            Button { mixer.toggleMute(row.id) } label: {
                Image(systemName: row.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: compact ? 9 : 11, weight: .semibold))
                    .foregroundStyle(row.muted ? Color.black : .white.opacity(0.85))
                    .frame(width: compact ? 20 : 26, height: compact ? 20 : 26)
                    .background(Circle().fill(row.muted ? .white : .white.opacity(0.1)))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .help(row.muted ? "Unmute \(row.name)" : "Mute \(row.name)")
        }
        .frame(width: compact ? 52 : 72)
    }

    @ViewBuilder private var icon: some View {
        let side: CGFloat = compact ? 16 : 26
        if let image = MixerIcons.icon(for: row.id) {
            Image(nsImage: image).resizable().frame(width: side, height: side)
        } else {
            Image(systemName: "app.fill").font(.system(size: compact ? 11 : 14)).frame(width: side, height: side)
        }
    }
}

/// Capsule fader. The top of the track is 100%.
private struct VolumeFader: View {
    var level: Int
    var enabled: Bool
    var onChange: (Int) -> Void
    @State private var dragging = false

    var body: some View {
        GeometryReader { g in
            let fraction = CGFloat(level) / 100
            ZStack(alignment: .bottom) {
                Capsule().fill(.white.opacity(0.16))
                Capsule().fill(.white.opacity(enabled ? 1 : 0.45))
                    .frame(height: level <= 0 ? 0 : max(dragging ? 8 : 6, g.size.height * fraction))
            }
            .frame(width: dragging ? 8 : 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard enabled, g.size.height > 0 else { return }
                dragging = true
                let fromTop = min(1, max(0, value.location.y / g.size.height))
                onChange(Int(((1 - fromTop) * 100).rounded()))
            }.onEnded { _ in dragging = false })
        }
        .frame(maxHeight: .infinity)
        .opacity(enabled ? 1 : 0.55)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: level)
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
