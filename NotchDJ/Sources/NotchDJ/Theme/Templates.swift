import SwiftUI

/// A look for the whole app plus a layout for the DJ tab.
///
/// Templates share `AppVolumeMixer`, `NowPlayingMonitor`, `MeterBank` and the controls; they
/// only choose tokens and arrange the DJ tab. To add one, see docs/DESIGN.md, "Adding a template".
protocol DJTemplate {
    var id: TemplateID { get }
    var name: String { get }
    var blurb: String { get }
    var supportsLight: Bool { get }
    var supportsDark: Bool { get }
    func tokens(dark: Bool) -> ThemeTokens
    /// The DJ tab. It reads the mixer and now playing from the environment.
    @MainActor func makeDJView() -> AnyView
}

enum TemplateID: String, CaseIterable, Identifiable, Sendable {
    case studio, ko, hardware, club, minimal
    var id: String { rawValue }

    var template: any DJTemplate {
        switch self {
        case .studio: return StudioTemplate()
        case .ko: return KOTemplate()
        case .hardware: return HardwareTemplate()
        case .club: return ClubTemplate()
        case .minimal: return MinimalTemplate()
        }
    }
}

struct StudioTemplate: DJTemplate {
    var id: TemplateID { .studio }
    var name: String { String(localized: "Studio") }
    var blurb: String { String(localized: "Clean and native, light or dark, in your accent color.") }
    var supportsLight: Bool { true }
    var supportsDark: Bool { true }

    func tokens(dark: Bool) -> ThemeTokens {
        let ink: Color = dark ? .white : Color(hex: 0x1D1D1F)
        return ThemeTokens(
            isDark: dark,
            panel: dark ? Color(hex: 0x0B0B0C) : Color(hex: 0xF2F2F4),
            header: Color(hex: 0x000000),
            headerText: .white,
            surface: dark ? Color(hex: 0x1C1C1E) : .white,
            raised: dark ? Color(hex: 0x2C2C2E) : Color(hex: 0xE5E5EA),
            line: ink.opacity(dark ? 0.12 : 0.1),
            text: ink,
            secondary: ink.opacity(0.62),
            tertiary: ink.opacity(0.38),
            accent: .accentColor,
            onAccent: .white,
            deckA: .accentColor,
            deckB: dark ? Color(hex: 0xFF9F0A) : Color(hex: 0xFF9500),
            meterLow: dark ? Color(hex: 0x30D158) : Color(hex: 0x28CD41),
            meterMid: dark ? Color(hex: 0xFFD60A) : Color(hex: 0xFFCC00),
            meterHot: dark ? Color(hex: 0xFF453A) : Color(hex: 0xFF3B30),
            meterOff: ink.opacity(0.08),
            panelRadius: 22,
            cardRadius: 14,
            controlRadius: 8,
            lineWidth: 1,
            textDesign: .default,
            labelTracking: 0.6,
            uppercaseLabels: true,
            knob: .arc,
            fader: .slim,
            meter: .bar,
            card: .filled
        )
    }

    @MainActor func makeDJView() -> AnyView { AnyView(StudioDJLayout()) }
}

struct KOTemplate: DJTemplate {
    var id: TemplateID { .ko }
    var name: String { String(localized: "K.O.") }
    var blurb: String { String(localized: "Off-white or black, one orange accent, thin line art.") }
    var supportsLight: Bool { true }
    var supportsDark: Bool { true }

    func tokens(dark: Bool) -> ThemeTokens {
        let paper = Color(hex: 0xECE9E2)
        let ink: Color = dark ? paper : Color(hex: 0x141414)
        let orange = Color(hex: 0xFF5A00)
        return ThemeTokens(
            isDark: dark,
            panel: dark ? Color(hex: 0x0A0A0A) : paper,
            header: Color(hex: 0x0A0A0A),
            headerText: paper,
            surface: dark ? Color(hex: 0x0A0A0A) : paper,
            raised: dark ? Color(hex: 0x1C1C1C) : Color(hex: 0xDDD9CF),
            line: ink.opacity(0.85),
            text: ink,
            secondary: ink.opacity(0.6),
            tertiary: ink.opacity(0.36),
            accent: orange,
            onAccent: .white,
            deckA: orange,
            deckB: ink,
            meterLow: ink,
            meterMid: ink,
            meterHot: orange,
            meterOff: ink.opacity(0.14),
            panelRadius: 18,
            cardRadius: 4,
            controlRadius: 2,
            lineWidth: 1,
            textDesign: .monospaced,
            labelTracking: 1,
            uppercaseLabels: true,
            knob: .line,
            fader: .line,
            meter: .segments,
            card: .outlined
        )
    }

    @MainActor func makeDJView() -> AnyView { AnyView(KODJLayout()) }
}

struct HardwareTemplate: DJTemplate {
    var id: TemplateID { .hardware }
    var name: String { String(localized: "Hardware Black") }
    var blurb: String { String(localized: "Matte black, white legends and amber LED rings, laid out like a club mixer.") }
    var supportsLight: Bool { false }
    var supportsDark: Bool { true }

    func tokens(dark: Bool) -> ThemeTokens {
        let amber = Color(hex: 0xFFB000)
        return ThemeTokens(
            isDark: true,
            panel: Color(hex: 0x0B0B0C),
            header: Color(hex: 0x000000),
            headerText: .white,
            surface: Color(hex: 0x141416),
            raised: Color(hex: 0x1F1F22),
            line: Color.white.opacity(0.1),
            text: .white,
            secondary: Color.white.opacity(0.7),
            tertiary: Color.white.opacity(0.4),
            accent: amber,
            onAccent: .black,
            deckA: amber,
            deckB: Color(hex: 0xFFD27A),
            meterLow: Color(hex: 0x3CE36A),
            meterMid: amber,
            meterHot: Color(hex: 0xFF3B30),
            meterOff: Color.white.opacity(0.07),
            panelRadius: 20,
            cardRadius: 6,
            controlRadius: 3,
            lineWidth: 1,
            textDesign: .default,
            labelTracking: 0.9,
            uppercaseLabels: true,
            knob: .ledRing,
            fader: .hardware,
            meter: .led,
            card: .filled
        )
    }

    @MainActor func makeDJView() -> AnyView { AnyView(HardwareDJLayout()) }
}

struct ClubTemplate: DJTemplate {
    var id: TemplateID { .club }
    var name: String { String(localized: "Club") }
    var blurb: String { String(localized: "Two platters with live level history and a big crossfader.") }
    var supportsLight: Bool { false }
    var supportsDark: Bool { true }

    func tokens(dark: Bool) -> ThemeTokens {
        let cyan = Color(hex: 0x00E5FF)
        let magenta = Color(hex: 0xFF2BD6)
        return ThemeTokens(
            isDark: true,
            panel: Color(hex: 0x050507),
            header: Color(hex: 0x000000),
            headerText: .white,
            surface: Color(hex: 0x101016),
            raised: Color(hex: 0x1B1B25),
            line: Color.white.opacity(0.09),
            text: .white,
            secondary: Color.white.opacity(0.66),
            tertiary: Color.white.opacity(0.38),
            accent: cyan,
            onAccent: .black,
            deckA: cyan,
            deckB: magenta,
            meterLow: cyan,
            meterMid: Color(hex: 0xB388FF),
            meterHot: magenta,
            meterOff: Color.white.opacity(0.07),
            panelRadius: 24,
            cardRadius: 18,
            controlRadius: 10,
            lineWidth: 1.5,
            textDesign: .rounded,
            labelTracking: 0.6,
            uppercaseLabels: true,
            knob: .solid,
            fader: .thick,
            meter: .bar,
            card: .filled
        )
    }

    @MainActor func makeDJView() -> AnyView { AnyView(ClubDJLayout()) }
}

struct MinimalTemplate: DJTemplate {
    var id: TemplateID { .minimal }
    var name: String { String(localized: "Minimal") }
    var blurb: String { String(localized: "One deck: volume and a filter. Follows the system appearance.") }
    var supportsLight: Bool { true }
    var supportsDark: Bool { true }

    func tokens(dark: Bool) -> ThemeTokens {
        var tokens = StudioTemplate().tokens(dark: dark)
        tokens.panel = dark ? Color(hex: 0x000000) : Color(hex: 0xFAFAFA)
        tokens.deckB = tokens.accent
        tokens.panelRadius = 24
        tokens.cardRadius = 16
        tokens.uppercaseLabels = false
        tokens.labelTracking = 0
        tokens.fader = .thick
        tokens.card = .plain
        return tokens
    }

    @MainActor func makeDJView() -> AnyView { AnyView(MinimalDJLayout()) }
}
