import AppKit
import SwiftUI

enum PanelSize: String, CaseIterable, Identifiable, Sendable {
    case compact, regular, large
    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return String(localized: "Compact")
        case .regular: return String(localized: "Regular")
        case .large: return String(localized: "Large")
        }
    }
}

/// Sizes for one panel size on one screen. See docs/DESIGN.md, "Sizes".
struct PanelMetrics: Equatable, Sendable {
    var size: PanelSize
    var width: CGFloat
    /// The whole open panel, including the band beside the notch.
    var height: CGFloat
    /// Height of the band beside the notch. Equal to the notch.
    var header: CGFloat
    var padding: CGFloat
    var knob: CGFloat
    var masterKnob: CGFloat
    /// Shortest fader in MIXER. Faders grow into any extra room.
    var fader: CGFloat
    var artwork: CGFloat
    var textScale: CGFloat

    var gap: CGFloat { 8 }
    var contentHeight: CGFloat { height - header - padding * 2 }
    var contentWidth: CGFloat { width - padding * 2 }

    static func make(_ size: PanelSize, screen: CGSize = CGSize(width: 1512, height: 982),
                     notchHeight: CGFloat = 32) -> PanelMetrics {
        let base: (width: CGFloat, height: CGFloat, padding: CGFloat, knob: CGFloat, master: CGFloat,
                   fader: CGFloat, artwork: CGFloat, text: CGFloat)
        switch size {
        case .compact: base = (720, 380, 16, 44, 96, 172, 120, 0.94)
        case .regular: base = (780, 420, 20, 48, 112, 212, 148, 1)
        case .large: base = (820, 460, 20, 54, 128, 252, 170, 1.08)
        }
        let header = max(24, notchHeight)
        let width = min(base.width, max(560, screen.width - 32))
        let height = min(base.height, max(340, screen.height * 0.62))
        let scale = min(1, width / base.width, height / base.height)
        return PanelMetrics(
            size: size,
            width: width.rounded(),
            height: height.rounded(),
            header: header,
            padding: base.padding,
            knob: max(44, (base.knob * scale).rounded()),
            masterKnob: max(88, (base.master * scale).rounded()),
            fader: max(160, (base.fader * scale).rounded()),
            artwork: max(96, (base.artwork * scale).rounded()),
            textScale: base.text
        )
    }
}

/// Animations from docs/DESIGN.md, "Motion". Each one has a Reduce Motion form.
@MainActor
enum Motion {
    static var reduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    static var openClose: Animation {
        reduce ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.82)
    }

    static var hover: Animation? {
        reduce ? nil : .spring(response: 0.3, dampingFraction: 0.7)
    }

    static var tab: Animation {
        reduce ? .easeOut(duration: 0.12) : .spring(response: 0.35, dampingFraction: 0.85)
    }

    static var step: Animation {
        reduce ? .easeOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.86)
    }
}
