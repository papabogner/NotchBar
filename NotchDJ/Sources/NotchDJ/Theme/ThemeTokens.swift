import SwiftUI

enum KnobLook: Sendable { case arc, line, ledRing, solid }
enum FaderLook: Sendable { case slim, line, hardware, thick }
enum MeterLook: Sendable { case bar, segments, led }
enum CardLook: Sendable { case filled, outlined, plain }

enum TextRole: Sendable {
    case display, title, body, caption, label, value, bigValue
}

/// Everything a template can change about color, shape and type. Controls read it from the
/// environment, so HOME, MIXER and onboarding follow the chosen template.
struct ThemeTokens {
    var isDark: Bool
    var panel: Color
    /// The band beside the hardware notch, where the tabs sit. Dark on every template.
    var header: Color
    var headerText: Color
    var surface: Color
    var raised: Color
    var line: Color
    var text: Color
    var secondary: Color
    var tertiary: Color
    var accent: Color
    var onAccent: Color
    var deckA: Color
    var deckB: Color
    var meterLow: Color
    var meterMid: Color
    var meterHot: Color
    var meterOff: Color
    var panelRadius: CGFloat
    var cardRadius: CGFloat
    var controlRadius: CGFloat
    var lineWidth: CGFloat
    var textDesign: Font.Design
    var labelTracking: CGFloat
    var uppercaseLabels: Bool
    var knob: KnobLook
    var fader: FaderLook
    var meter: MeterLook
    var card: CardLook

    func deck(_ side: DeckSide) -> Color { side == .a ? deckA : deckB }

    func font(_ role: TextRole, scale: CGFloat) -> Font {
        switch role {
        case .display: return .system(size: 22 * scale, weight: .semibold, design: textDesign)
        case .title: return .system(size: 15 * scale, weight: .semibold, design: textDesign)
        case .body: return .system(size: 13 * scale, weight: .regular, design: textDesign)
        case .caption: return .system(size: 11 * scale, weight: .regular, design: textDesign)
        case .label: return .system(size: 10 * scale, weight: .semibold, design: textDesign)
        case .value: return .system(size: 12 * scale, weight: .medium, design: .monospaced)
        case .bigValue: return .system(size: 26 * scale, weight: .light, design: .monospaced)
        }
    }

    /// Meter color for a normalized level.
    func meterColor(_ level: Float) -> Color {
        if level > 0.92 { return meterHot }
        if level > 0.75 { return meterMid }
        return meterLow
    }
}

extension Color {
    /// sRGB from 0xRRGGBB.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: opacity)
    }
}

private struct ThemeTokensKey: EnvironmentKey {
    static var defaultValue: ThemeTokens { StudioTemplate().tokens(dark: true) }
}

private struct PanelMetricsKey: EnvironmentKey {
    static var defaultValue: PanelMetrics { PanelMetrics.make(.regular) }
}

extension EnvironmentValues {
    var djTokens: ThemeTokens {
        get { self[ThemeTokensKey.self] }
        set { self[ThemeTokensKey.self] = newValue }
    }

    var panelMetrics: PanelMetrics {
        get { self[PanelMetricsKey.self] }
        set { self[PanelMetricsKey.self] = newValue }
    }
}

private struct DJFontModifier: ViewModifier {
    @Environment(\.djTokens) private var tokens
    @Environment(\.panelMetrics) private var metrics
    let role: TextRole

    func body(content: Content) -> some View {
        let label = role == .label
        content
            .font(tokens.font(role, scale: metrics.textScale))
            .tracking(label ? tokens.labelTracking : 0)
            .textCase(label && tokens.uppercaseLabels ? .uppercase : nil)
    }
}

/// A card in the template's style: filled, outlined, or nothing.
private struct DJCardModifier: ViewModifier {
    @Environment(\.djTokens) private var tokens
    let padding: CGFloat
    let raised: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: tokens.cardRadius, style: .continuous)
        content
            .padding(padding)
            .background {
                switch tokens.card {
                case .filled:
                    shape.fill(raised ? tokens.raised : tokens.surface)
                case .outlined:
                    shape.strokeBorder(tokens.line, lineWidth: tokens.lineWidth)
                case .plain:
                    Color.clear
                }
            }
    }
}

extension View {
    func djFont(_ role: TextRole) -> some View {
        modifier(DJFontModifier(role: role))
    }

    func djCard(padding: CGFloat = 12, raised: Bool = false) -> some View {
        modifier(DJCardModifier(padding: padding, raised: raised))
    }
}
