import AppKit
import SwiftUI

/// How the notch is painted. Closed, it stays black so it matches the hardware.
@MainActor
final class NotchAppearance: ObservableObject {
    struct Theme: Equatable, Codable {
        enum Preset: String, Codable, CaseIterable, Identifiable {
            case classic, glass, neon, console, custom
            var id: String { rawValue }
            var title: String {
                switch self {
                case .classic: return "Midnight"
                case .glass: return "Liquid Glass"
                case .neon: return "Neon"
                case .console: return "Console"
                case .custom: return "Custom"
                }
            }
        }

        enum BackgroundStyle: String, Codable, CaseIterable, Identifiable {
            case black, glass, tintedGlass, gradient
            var id: String { rawValue }
            var title: String {
                switch self {
                case .black: return "Black"
                case .glass: return "Glass"
                case .tintedGlass: return "Tinted Glass"
                case .gradient: return "Gradient"
                }
            }
        }

        enum FontChoice: String, Codable, CaseIterable, Identifiable {
            case system, rounded, monospaced, serif
            var id: String { rawValue }
            var title: String {
                switch self {
                case .system: return "System"
                case .rounded: return "Rounded"
                case .monospaced: return "Monospaced"
                case .serif: return "Serif"
                }
            }
            var design: Font.Design {
                switch self {
                case .system: return .default
                case .rounded: return .rounded
                case .monospaced: return .monospaced
                case .serif: return .serif
                }
            }
        }

        enum TextSize: String, Codable, CaseIterable, Identifiable {
            case s, m, l
            var id: String { rawValue }
            var title: String { rawValue.uppercased() }
            var scale: CGFloat {
                switch self {
                case .s: return 0.92
                case .m: return 1
                case .l: return 1.12
                }
            }
        }

        enum Density: String, Codable, CaseIterable, Identifiable {
            case compact, comfortable
            var id: String { rawValue }
            var title: String { rawValue.capitalized }
            var spacing: CGFloat { self == .compact ? 4 : 8 }
        }

        enum FaderStyle: String, Codable, CaseIterable, Identifiable {
            case line, pill, tall
            var id: String { rawValue }
            var title: String {
                switch self {
                case .line: return "Thin"
                case .pill: return "Pill"
                case .tall: return "Tall"
                }
            }
        }

        var preset: Preset = .classic
        var accentR = 1.0, accentG = 1.0, accentB = 1.0
        var bgR = 0.0, bgG = 0.0, bgB = 0.0
        var bg2R = 0.12, bg2G = 0.12, bg2B = 0.14
        var angle = 90.0
        var albumColors = false
        var backgroundStyle: BackgroundStyle = .black
        var tintR = 0.55, tintG = 0.72, tintB = 1.0
        var fontChoice: FontChoice = .system
        var textSize: TextSize = .m
        var cornerRadius = 30.0
        var density: Density = .comfortable
        var glassIntensity = 0.8
        var faderStyle: FaderStyle = .pill
        var glow = false

        static let classic = Theme()
        static let glass: Theme = {
            var theme = Theme()
            theme.preset = .glass
            theme.backgroundStyle = .glass
            theme.accentR = 0.75; theme.accentG = 0.88; theme.accentB = 1
            theme.fontChoice = .rounded
            return theme
        }()
        static let neon: Theme = {
            var theme = Theme()
            theme.preset = .neon
            theme.backgroundStyle = .gradient
            theme.accentR = 0.2; theme.accentG = 1; theme.accentB = 0.65
            theme.bgR = 0.02; theme.bgG = 0.04; theme.bgB = 0.05
            theme.bg2R = 0; theme.bg2G = 0.18; theme.bg2B = 0.12
            theme.angle = 120
            theme.fontChoice = .monospaced
            theme.faderStyle = .line
            theme.glow = true
            return theme
        }()
        static let console: Theme = {
            var theme = Theme()
            theme.preset = .console
            theme.accentR = 1; theme.accentG = 0.55; theme.accentB = 0.2
            theme.bgR = 0.09; theme.bgG = 0.07; theme.bgB = 0.05
            theme.bg2R = 0.16; theme.bg2G = 0.11; theme.bg2B = 0.07
            theme.angle = 180
            theme.cornerRadius = 16
            theme.faderStyle = .pill
            return theme
        }()
        /// Warm amber glass. A named look, not a saved preference.
        static let pabo: Theme = {
            var theme = Theme()
            theme.preset = .custom
            theme.backgroundStyle = .tintedGlass
            theme.accentR = 1; theme.accentG = 0.62; theme.accentB = 0.28
            theme.tintR = 0.85; theme.tintG = 0.42; theme.tintB = 0.12
            theme.fontChoice = .rounded
            theme.faderStyle = .tall
            theme.glassIntensity = 0.72
            theme.glow = true
            return theme
        }()
        static let paper: Theme = {
            var theme = Theme()
            theme.preset = .custom
            theme.backgroundStyle = .gradient
            theme.accentR = 0.98; theme.accentG = 0.94; theme.accentB = 0.86
            theme.bgR = 0.16; theme.bgG = 0.14; theme.bgB = 0.12
            theme.bg2R = 0.28; theme.bg2G = 0.24; theme.bg2B = 0.2
            theme.fontChoice = .serif
            theme.faderStyle = .line
            theme.cornerRadius = 22
            return theme
        }()

        var accent: Color { Color(red: accentR, green: accentG, blue: accentB) }
        var background: Color { Color(red: bgR, green: bgG, blue: bgB) }
        var backgroundEnd: Color { Color(red: bg2R, green: bg2G, blue: bg2B) }
        var tint: Color { Color(red: tintR, green: tintG, blue: tintB) }
        var faderCorner: CGFloat {
            switch faderStyle {
            case .line: return 3
            case .pill: return preset == .console ? 8 : 18
            case .tall: return 28
            }
        }
        var faderWidthScale: CGFloat {
            switch faderStyle {
            case .line: return 0.62
            case .pill: return 1
            case .tall: return 1.08
            }
        }
        var usesGlass: Bool { backgroundStyle == .glass || backgroundStyle == .tintedGlass }

        func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size * textSize.scale, weight: weight, design: fontChoice.design)
        }

        init() {}

        init(from decoder: Decoder) throws {
            let keys = try decoder.container(keyedBy: CodingKeys.self)
            preset = try keys.decodeIfPresent(Preset.self, forKey: .preset) ?? .classic
            accentR = try keys.decodeIfPresent(Double.self, forKey: .accentR) ?? 1
            accentG = try keys.decodeIfPresent(Double.self, forKey: .accentG) ?? 1
            accentB = try keys.decodeIfPresent(Double.self, forKey: .accentB) ?? 1
            bgR = try keys.decodeIfPresent(Double.self, forKey: .bgR) ?? 0
            bgG = try keys.decodeIfPresent(Double.self, forKey: .bgG) ?? 0
            bgB = try keys.decodeIfPresent(Double.self, forKey: .bgB) ?? 0
            bg2R = try keys.decodeIfPresent(Double.self, forKey: .bg2R) ?? 0.12
            bg2G = try keys.decodeIfPresent(Double.self, forKey: .bg2G) ?? 0.12
            bg2B = try keys.decodeIfPresent(Double.self, forKey: .bg2B) ?? 0.14
            angle = try keys.decodeIfPresent(Double.self, forKey: .angle) ?? 90
            albumColors = try keys.decodeIfPresent(Bool.self, forKey: .albumColors) ?? false
            fontChoice = try keys.decodeIfPresent(FontChoice.self, forKey: .fontChoice) ?? .system
            textSize = try keys.decodeIfPresent(TextSize.self, forKey: .textSize) ?? .m
            cornerRadius = try keys.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? (preset == .console ? 16 : 30)
            density = try keys.decodeIfPresent(Density.self, forKey: .density) ?? .comfortable
            glassIntensity = try keys.decodeIfPresent(Double.self, forKey: .glassIntensity) ?? 0.8
            faderStyle = try keys.decodeIfPresent(FaderStyle.self, forKey: .faderStyle) ?? (preset == .neon ? .line : .pill)
            glow = try keys.decodeIfPresent(Bool.self, forKey: .glow) ?? (preset == .neon)
            tintR = try keys.decodeIfPresent(Double.self, forKey: .tintR) ?? 0.55
            tintG = try keys.decodeIfPresent(Double.self, forKey: .tintG) ?? 0.72
            tintB = try keys.decodeIfPresent(Double.self, forKey: .tintB) ?? 1
            if let style = try keys.decodeIfPresent(BackgroundStyle.self, forKey: .backgroundStyle) {
                backgroundStyle = style
            } else {
                switch preset {
                case .glass: backgroundStyle = .glass
                case .neon, .custom: backgroundStyle = .gradient
                case .classic, .console: backgroundStyle = .black
                }
            }
        }

        func encode(to encoder: Encoder) throws {
            var keys = encoder.container(keyedBy: CodingKeys.self)
            try keys.encode(preset, forKey: .preset)
            try keys.encode(accentR, forKey: .accentR)
            try keys.encode(accentG, forKey: .accentG)
            try keys.encode(accentB, forKey: .accentB)
            try keys.encode(bgR, forKey: .bgR)
            try keys.encode(bgG, forKey: .bgG)
            try keys.encode(bgB, forKey: .bgB)
            try keys.encode(bg2R, forKey: .bg2R)
            try keys.encode(bg2G, forKey: .bg2G)
            try keys.encode(bg2B, forKey: .bg2B)
            try keys.encode(angle, forKey: .angle)
            try keys.encode(albumColors, forKey: .albumColors)
            try keys.encode(backgroundStyle, forKey: .backgroundStyle)
            try keys.encode(tintR, forKey: .tintR)
            try keys.encode(tintG, forKey: .tintG)
            try keys.encode(tintB, forKey: .tintB)
            try keys.encode(fontChoice, forKey: .fontChoice)
            try keys.encode(textSize, forKey: .textSize)
            try keys.encode(cornerRadius, forKey: .cornerRadius)
            try keys.encode(density, forKey: .density)
            try keys.encode(glassIntensity, forKey: .glassIntensity)
            try keys.encode(faderStyle, forKey: .faderStyle)
            try keys.encode(glow, forKey: .glow)
        }
    }

    @Published var theme: Theme {
        didSet { persist() }
    }

    private static let key = "notchTheme"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Theme.self, from: data) {
            theme = saved
        } else {
            theme = .classic
        }
    }

    func apply(_ preset: Theme.Preset) {
        switch preset {
        case .classic: theme = .classic
        case .glass: theme = .glass
        case .neon: theme = .neon
        case .console: theme = .console
        case .custom:
            var next = theme
            next.preset = .custom
            theme = next
        }
    }

    func applyLook(_ name: String) {
        switch name {
        case "Midnight": apply(.classic)
        case "Liquid Glass": apply(.glass)
        case "Neon": apply(.neon)
        case "Paper": theme = .paper
        case "Pabo": theme = .pabo
        default: break
        }
    }

    func reset() { theme = .classic }

    func setAccent(_ color: Color) { paint(color) { $0.accentR = $1.r; $0.accentG = $1.g; $0.accentB = $1.b } }
    func setTint(_ color: Color) {
        paint(color) { theme, parts in
            theme.tintR = parts.r; theme.tintG = parts.g; theme.tintB = parts.b
            theme.backgroundStyle = .tintedGlass
        }
    }
    func setBackground(_ color: Color, end: Bool) {
        paint(color) { theme, parts in
            if end {
                theme.bg2R = parts.r; theme.bg2G = parts.g; theme.bg2B = parts.b
            } else {
                theme.bgR = parts.r; theme.bgG = parts.g; theme.bgB = parts.b
            }
            theme.backgroundStyle = .gradient
        }
    }

    func setStyle(_ style: Theme.BackgroundStyle) {
        var next = theme
        next.backgroundStyle = style
        next.preset = style == .glass ? .glass : .custom
        if style == .black { next.preset = .classic }
        theme = next
    }

    /// Accent and background drawn from the current artwork when Album colors is on.
    func displayed(album: NSColor?) -> Theme {
        guard theme.albumColors, let album, let rgb = album.usingColorSpace(.sRGB) else { return theme }
        var next = theme
        next.accentR = Double(rgb.redComponent)
        next.accentG = Double(rgb.greenComponent)
        next.accentB = Double(rgb.blueComponent)
        next.bgR = next.accentR * 0.18
        next.bgG = next.accentG * 0.18
        next.bgB = next.accentB * 0.18
        next.bg2R = next.accentR * 0.45
        next.bg2G = next.accentG * 0.45
        next.bg2B = next.accentB * 0.45
        next.tintR = next.accentR
        next.tintG = next.accentG
        next.tintB = next.accentB
        return next
    }

    private func paint(_ color: Color, _ apply: (inout Theme, (r: Double, g: Double, b: Double)) -> Void) {
        let parts = Self.components(color)
        var next = theme
        next.preset = .custom
        apply(&next, parts)
        theme = next
    }

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(theme), forKey: Self.key)
    }

    private static func components(_ color: Color) -> (r: Double, g: Double, b: Double) {
        let resolved = color.resolve(in: EnvironmentValues())
        return (Double(resolved.red), Double(resolved.green), Double(resolved.blue))
    }
}

private struct NotchChromeKey: EnvironmentKey {
    static let defaultValue = NotchAppearance.Theme.classic
}

extension EnvironmentValues {
    var notchChrome: NotchAppearance.Theme {
        get { self[NotchChromeKey.self] }
        set { self[NotchChromeKey.self] = newValue }
    }
}

/// System glass for the expanded body. macOS 26 uses the real glass effect; earlier systems blur.
struct NotchSystemGlass: View {
    var tint: Color?
    var intensity: Double

    var body: some View {
        if #available(macOS 26.0, *) {
            LiquidGlass(tint: tint, intensity: intensity)
        } else {
            FallbackGlass(intensity: intensity)
        }
    }
}

@available(macOS 26.0, *)
private struct LiquidGlass: View {
    var tint: Color?
    var intensity: Double

    var body: some View {
        let glass = tint == nil ? Glass.regular : Glass.regular.tint((tint ?? .clear).opacity(0.35 + intensity * 0.4))
        Color.clear
            .glassEffect(glass, in: Rectangle())
            .opacity(0.55 + intensity * 0.45)
    }
}

private struct FallbackGlass: NSViewRepresentable {
    var intensity: Double

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = intensity > 0.65 ? .hudWindow : .popover
        view.alphaValue = CGFloat(0.72 + intensity * 0.28)
    }
}
