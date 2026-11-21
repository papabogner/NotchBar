import SwiftUI

/// Apps that are playing, each with its own volume. Hidden below macOS 14.4.
struct MixerPanel: View {
    @ObservedObject var mixer: AppVolumeMixer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Playing")
                if mixer.needsExplanation { explanation }
                if mixer.permissionDenied { denied }
                if mixer.showSavedHint {
                    Text("Move a slider to apply saved levels.")
                        .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5))
                }
                if mixer.rows.isEmpty {
                    empty
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(mixer.rows) { MixerRow(row: $0, mixer: mixer) }
                    }
                }
                if let status = mixer.statusMessage, !mixer.permissionDenied {
                    Text(status).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
            Text("NotchBar listens to an app only while its slider isn't at 100%, then plays it at that level. Audio isn't recorded or stored. macOS asks the next time you move a slider.")
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
            Text("The app was left at its normal volume. Turn on system audio recording for NotchBar in Privacy & Security. Nothing is recorded or stored.")
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

private struct MixerRow: View {
    let row: AppVolumeRow
    @ObservedObject var mixer: AppVolumeMixer

    var body: some View {
        HStack(spacing: 10) {
            icon
            Text(row.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                .frame(width: 128, alignment: .leading)
            VolumeSlider(level: row.muted ? 0 : row.level, enabled: !row.muted) { mixer.setLevel(row.id, $0) }
                .accessibilityLabel("\(row.name) volume")
            Text(row.muted ? "Off" : "\(row.level)")
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 32, alignment: .trailing)
            Button { mixer.toggleMute(row.id) } label: {
                Image(systemName: row.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(row.muted ? Color.black : .white.opacity(0.85))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(row.muted ? .white : .white.opacity(0.1)))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .help(row.muted ? "Unmute \(row.name)" : "Mute \(row.name)")
        }
        .frame(height: 32)
    }

    @ViewBuilder private var icon: some View {
        if let image = MixerIcons.icon(for: row.id) {
            Image(nsImage: image).resizable().frame(width: 22, height: 22)
        } else {
            Image(systemName: "app.fill").font(.system(size: 14)).frame(width: 22, height: 22)
        }
    }
}

/// The same capsule as the volume HUD, in points from 0 to 100.
private struct VolumeSlider: View {
    var level: Int
    var enabled: Bool
    var onChange: (Int) -> Void
    @State private var dragging = false

    var body: some View {
        GeometryReader { g in
            let fraction = CGFloat(level) / 100
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                Capsule().fill(.white.opacity(enabled ? 1 : 0.45))
                    .frame(width: level <= 0 ? 0 : max(dragging ? 8 : 6, g.size.width * fraction))
            }
            .frame(height: dragging ? 8 : 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard enabled else { return }
                dragging = true
                let fraction = min(1, max(0, value.location.x / max(g.size.width, 1)))
                onChange(Int((fraction * 100).rounded()))
            }.onEnded { _ in dragging = false })
        }
        .frame(height: 22)
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
        icon.size = NSSize(width: 22, height: 22)
        cache[bundleID] = icon
        return icon
    }
}
