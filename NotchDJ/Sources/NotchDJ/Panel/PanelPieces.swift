import AppKit
import SwiftUI

// MARK: Labels and buttons

/// Small caps label in the template's type.
struct SectionLabel: View {
    let text: String
    var color: Color?

    @Environment(\.djTokens) private var tokens

    init(_ text: String, color: Color? = nil) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .djFont(.label)
            .foregroundStyle(color ?? tokens.tertiary)
            .lineLimit(1)
    }
}

/// A square pad for CUE, M and S. Lit in `tint` while active.
struct PadButton: View {
    let title: String
    let active: Bool
    var tint: Color?
    var width: CGFloat = 34
    var height: CGFloat = 26
    var help: String = ""
    let action: @MainActor () -> Void

    @Environment(\.djTokens) private var tokens

    var body: some View {
        let color = tint ?? tokens.accent
        let shape = RoundedRectangle(cornerRadius: tokens.controlRadius, style: .continuous)
        Button {
            action()
        } label: {
            Text(title)
                .djFont(.label)
                .foregroundStyle(active ? tokens.onAccent : tokens.secondary)
                .frame(width: width, height: height)
                .background {
                    if active {
                        shape.fill(color)
                    } else if tokens.card == .outlined {
                        shape.strokeBorder(tokens.line, lineWidth: tokens.lineWidth)
                    } else {
                        shape.fill(tokens.raised)
                    }
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .help(help.isEmpty ? title : help)
        .accessibilityLabel(help.isEmpty ? title : help)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// A text button in the template's accent, for banners and cards.
struct ChipButton: View {
    let title: String
    var prominent = false
    var systemImage: String?
    let action: @MainActor () -> Void

    @Environment(\.djTokens) private var tokens

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: tokens.controlRadius + 2, style: .continuous)
        Button {
            action()
        } label: {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold, design: tokens.textDesign))
            .foregroundStyle(prominent ? tokens.onAccent : tokens.text)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background {
                if prominent {
                    shape.fill(tokens.accent)
                } else {
                    shape.strokeBorder(tokens.line, lineWidth: tokens.lineWidth)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}

// MARK: Banners

/// Permission requests, a refused permission and errors, above the tab content.
struct PermissionBanner: View {
    @EnvironmentObject private var model: DJModel
    @EnvironmentObject private var mixer: AppVolumeMixer
    @EnvironmentObject private var permissions: PermissionCenter

    var body: some View {
        if mixer.needsExplanation {
            BannerRow(
                systemImage: "waveform",
                title: String(localized: "Allow audio access"),
                message: String(localized: "Notch DJ changes one app's volume by tapping its audio (System Audio Recording). The audio is processed live on this Mac and never leaves it."),
                primary: (String(localized: "Allow"), { model.allowCapture() }),
                secondary: (String(localized: "Not Now"), { mixer.declineExplanation() })
            )
        } else if mixer.permissionDenied {
            BannerRow(
                systemImage: "exclamationmark.triangle",
                title: String(localized: "System Audio Recording is off"),
                message: String(localized: "Turn on Notch DJ in Privacy & Security › Screen & System Audio Recording. Until then every app plays at its normal volume."),
                primary: (String(localized: "Open Settings"), { permissions.openCaptureSettings() }),
                secondary: (String(localized: "Check Again"), { permissions.refresh(force: true) })
            )
        } else if let message = mixer.statusMessage {
            BannerRow(
                systemImage: "info.circle",
                title: nil,
                message: message,
                primary: nil,
                secondary: (String(localized: "Dismiss"), { mixer.dismissStatus() })
            )
        }
    }
}

struct BannerRow: View {
    let systemImage: String
    let title: String?
    let message: String
    let primary: (String, @MainActor () -> Void)?
    let secondary: (String, @MainActor () -> Void)?

    @Environment(\.djTokens) private var tokens

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tokens.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                if let title {
                    Text(title).djFont(.body).fontWeight(.semibold)
                }
                Text(message)
                    .djFont(.caption)
                    .foregroundStyle(tokens.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let secondary {
                ChipButton(title: secondary.0, action: secondary.1)
            }
            if let primary {
                ChipButton(title: primary.0, prominent: true, action: primary.1)
            }
        }
        .djCard(padding: 10, raised: true)
        .transition(.opacity)
    }
}

// MARK: Artwork

/// Track artwork, or the app's icon on a plain tile.
struct ArtworkView: View {
    let image: NSImage?
    let bundleID: String?
    let size: CGFloat
    var radius: CGFloat?

    @Environment(\.djTokens) private var tokens

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius ?? tokens.cardRadius, style: .continuous)
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                shape.fill(tokens.raised)
                if bundleID != nil {
                    AppIconView(bundleID: bundleID, size: size * 0.42)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.3, weight: .light))
                        .foregroundStyle(tokens.tertiary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay {
            if tokens.card == .outlined { shape.strokeBorder(tokens.line, lineWidth: tokens.lineWidth) }
        }
        .accessibilityHidden(true)
    }
}

// MARK: Menus

/// Picks the app on a deck. Lists every app with an audio process.
struct DeckSourceMenu<Face: View>: View {
    let side: DeckSide
    @ViewBuilder let label: () -> Face

    @EnvironmentObject private var mixer: AppVolumeMixer

    var body: some View {
        Menu {
            let current = mixer.deckID(side)
            ForEach(mixer.rows) { row in
                Button {
                    mixer.assign(side, row.id)
                } label: {
                    if row.id == current {
                        SwiftUI.Label(row.name, systemImage: "checkmark")
                    } else {
                        Text(row.name)
                    }
                }
            }
            if mixer.rows.isEmpty {
                Text("No app is playing")
            }
            if current != nil {
                Divider()
                Button("Empty Deck \(side.letter)") { mixer.assign(side, nil) }
            }
        } label: {
            label()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// Routes one app to an output, or back to the system default.
struct AppOutputMenu: View {
    let bundleID: String

    @EnvironmentObject private var mixer: AppVolumeMixer
    @Environment(\.djTokens) private var tokens

    var body: some View {
        let route = mixer.route(for: bundleID)
        Menu {
            Button {
                mixer.setAppOutput(bundleID, uid: nil)
            } label: {
                if route == nil {
                    SwiftUI.Label("System Output", systemImage: "checkmark")
                } else {
                    Text("System Output")
                }
            }
            Divider()
            ForEach(mixer.outputChoices) { device in
                Button {
                    mixer.setAppOutput(bundleID, uid: device.uid)
                } label: {
                    if route == device.uid {
                        SwiftUI.Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
        } label: {
            Image(systemName: route == nil ? "speaker.wave.2" : "airplayaudio")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(route == nil ? tokens.tertiary : tokens.accent)
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text("Output"))
    }
}

/// The system output device, for HOME and the master strip.
struct SystemOutputMenu: View {
    /// Only the device symbol, for narrow places.
    var compact = false

    @EnvironmentObject private var mixer: AppVolumeMixer
    @Environment(\.djTokens) private var tokens

    var body: some View {
        let current = mixer.currentOutputUID()
        Menu {
            ForEach(mixer.outputChoices) { device in
                Button {
                    mixer.setSystemOutput(uid: device.uid)
                } label: {
                    if device.uid == current {
                        SwiftUI.Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: mixer.master.symbol)
                if !compact {
                    Text(mixer.master.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(tokens.tertiary)
            }
            .font(.system(size: 12, weight: .medium, design: tokens.textDesign))
            .foregroundStyle(tokens.text)
            .padding(.horizontal, compact ? 7 : 10)
            .frame(height: compact ? 22 : 26)
            .background(
                RoundedRectangle(cornerRadius: tokens.controlRadius + 2, style: .continuous)
                    .strokeBorder(tokens.line, lineWidth: tokens.lineWidth)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help(Text(verbatim: compact ? mixer.master.name : String(localized: "Output device")))
    }
}

// MARK: Transport

/// Previous, play/pause and next for what is playing.
struct TransportButtons: View {
    var size: CGFloat = 15
    var enabled = true

    @EnvironmentObject private var now: NowPlayingMonitor
    @Environment(\.djTokens) private var tokens

    var body: some View {
        let playing = now.entry?.isPlaying == true
        let canSkip = now.entry?.source.canSkip ?? true
        HStack(spacing: size * 1.1) {
            button("backward.fill", String(localized: "Previous")) { now.previous() }
                .disabled(!canSkip)
            button(playing ? "pause.fill" : "play.fill", playing ? String(localized: "Pause") : String(localized: "Play"),
                   scale: 1.35) { now.togglePlay() }
            button("forward.fill", String(localized: "Next")) { now.next() }
                .disabled(!canSkip)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private func button(_ symbol: String, _ label: String, scale: CGFloat = 1,
                        action: @escaping @MainActor () -> Void) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size * scale, weight: .semibold))
                .frame(width: size * 2, height: size * 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Elapsed time and a seek bar, when the player reports a timeline. Ticks once a second while playing.
struct Scrubber: View {
    let entry: NowPlaying

    @EnvironmentObject private var now: NowPlayingMonitor
    @Environment(\.djTokens) private var tokens
    @State private var dragValue: Double?

    var body: some View {
        Group {
            if entry.isPlaying {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    bar(at: context.date)
                }
            } else {
                bar(at: Date())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Position"))
        .accessibilityValue(Text(verbatim: Self.time(entry.elapsed(at: Date()))))
        .accessibilityAdjustableAction { direction in
            let step: Double = direction == .increment ? 10 : -10
            now.seek(to: entry.elapsed(at: Date()) + step)
        }
    }

    private func bar(at date: Date) -> some View {
        let elapsed = dragValue ?? entry.elapsed(at: date)
        let fraction = entry.duration > 0 ? min(1, max(0, elapsed / entry.duration)) : 0
        return VStack(spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(tokens.raised)
                    Capsule().fill(tokens.accent).frame(width: max(4, proxy.size.width * fraction))
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let x = min(max(0, value.location.x), proxy.size.width)
                            dragValue = Double(x / max(1, proxy.size.width)) * entry.duration
                        }
                        .onEnded { _ in
                            if let target = dragValue { now.seek(to: target) }
                            dragValue = nil
                        }
                )
            }
            .frame(height: 12)
            HStack {
                Text(verbatim: Self.time(elapsed))
                Spacer()
                Text(verbatim: Self.time(entry.duration))
            }
            .djFont(.value)
            .foregroundStyle(tokens.tertiary)
        }
    }

    nonisolated static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%ld:%02ld", total / 60, total % 60)
    }
}
