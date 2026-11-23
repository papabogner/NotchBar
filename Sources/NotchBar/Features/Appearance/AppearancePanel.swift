import SwiftUI

/// Live appearance controls. Opened from the … menu.
struct AppearancePanel: View {
    @ObservedObject var appearance: NotchAppearance
    var close: () -> Void
    var embedded = false

    private static let swatches: [Color] = [
        .white, Color(red: 0.75, green: 0.88, blue: 1), Color(red: 0.2, green: 1, blue: 0.65),
        Color(red: 1, green: 0.62, blue: 0.28), Color(red: 1, green: 0.35, blue: 0.45),
        Color(red: 0.65, green: 0.45, blue: 1), Color(red: 0.35, green: 0.75, blue: 1),
        Color(red: 0.98, green: 0.94, blue: 0.86), Color(red: 1, green: 0.85, blue: 0.2),
        Color(red: 0.55, green: 0.9, blue: 0.7)
    ]
    private static let looks = ["Midnight", "Liquid Glass", "Neon", "Paper", "Pabo"]

    var body: some View {
        let theme = appearance.theme
        ScrollView {
            VStack(alignment: .leading, spacing: theme.density.spacing + 6) {
                if !embedded {
                    HStack {
                        Text("Appearance").font(theme.font(15, weight: .semibold))
                        Spacer()
                        Button("Done", action: close).buttonStyle(PressableStyle(scale: 0.96))
                            .font(theme.font(12, weight: .semibold))
                    }
                }
                Text("Presets").font(theme.font(11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 6) {
                    ForEach(Self.looks, id: \.self) { name in
                        Button { appearance.applyLook(name) } label: {
                            Text(name).font(theme.font(11, weight: .semibold))
                                .padding(.horizontal, 8).frame(height: 26)
                                .background(Capsule().fill(.white.opacity(0.12)))
                        }
                        .buttonStyle(PressableStyle(scale: 0.95))
                    }
                    Button("Reset") { appearance.reset() }
                        .buttonStyle(PressableStyle(scale: 0.95))
                        .font(theme.font(11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Text("Background").font(theme.font(11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 6) {
                    ForEach(NotchAppearance.Theme.BackgroundStyle.allCases) { style in
                        Button { appearance.setStyle(style) } label: {
                            Text(style.title).font(theme.font(11, weight: .semibold))
                                .padding(.horizontal, 8).frame(height: 26)
                                .background(Capsule().fill(theme.backgroundStyle == style ? theme.accent : .white.opacity(0.1)))
                                .foregroundStyle(theme.backgroundStyle == style ? .black : .white)
                        }
                        .buttonStyle(PressableStyle(scale: 0.95))
                    }
                }
                if theme.backgroundStyle == .tintedGlass {
                    ColorPicker("Tint", selection: Binding(get: { theme.tint }, set: { appearance.setTint($0) }), supportsOpacity: false)
                        .font(theme.font(12))
                }
                if theme.backgroundStyle == .gradient {
                    HStack {
                        ColorPicker("Start", selection: Binding(get: { theme.background }, set: { appearance.setBackground($0, end: false) }), supportsOpacity: false)
                        ColorPicker("End", selection: Binding(get: { theme.backgroundEnd }, set: { appearance.setBackground($0, end: true) }), supportsOpacity: false)
                    }
                    .font(theme.font(12))
                    labeled("Angle", value: "\(Int(theme.angle))°", theme: theme) {
                        Slider(value: binding(\.angle), in: 0...360)
                    }
                }
                labeled("Glass", value: "\(Int(theme.glassIntensity * 100))", theme: theme) {
                    Slider(value: binding(\.glassIntensity), in: 0.35...1)
                }
                Text("Accent").font(theme.font(11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 6) {
                    ForEach(Array(Self.swatches.enumerated()), id: \.offset) { _, swatch in
                        Button { appearance.setAccent(swatch) } label: {
                            Circle().fill(swatch).frame(width: 16, height: 16)
                                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 0.5))
                        }
                        .buttonStyle(PressableStyle(scale: 0.9))
                    }
                    ColorPicker("", selection: Binding(get: { theme.accent }, set: { appearance.setAccent($0) }), supportsOpacity: false)
                        .labelsHidden()
                }
                Toggle("Album colors", isOn: Binding(get: { theme.albumColors }, set: { value in
                    var next = appearance.theme
                    next.albumColors = value
                    appearance.theme = next
                }))
                .toggleStyle(.switch)
                .font(theme.font(12, weight: .medium))
                Text("Type").font(theme.font(11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 6) {
                    ForEach(NotchAppearance.Theme.FontChoice.allCases) { choice in
                        choiceButton(choice.title, on: theme.fontChoice == choice) {
                            var next = appearance.theme
                            next.fontChoice = choice
                            appearance.theme = next
                        }
                    }
                    ForEach(NotchAppearance.Theme.TextSize.allCases) { size in
                        choiceButton(size.title, on: theme.textSize == size) {
                            var next = appearance.theme
                            next.textSize = size
                            appearance.theme = next
                        }
                    }
                }
                Text("Faders").font(theme.font(11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 6) {
                    ForEach(NotchAppearance.Theme.FaderStyle.allCases) { style in
                        choiceButton(style.title, on: theme.faderStyle == style) {
                            var next = appearance.theme
                            next.faderStyle = style
                            appearance.theme = next
                        }
                    }
                    ForEach(NotchAppearance.Theme.Density.allCases) { density in
                        choiceButton(density.title, on: theme.density == density) {
                            var next = appearance.theme
                            next.density = density
                            appearance.theme = next
                        }
                    }
                }
                labeled("Corners", value: "\(Int(theme.cornerRadius))", theme: theme) {
                    Slider(value: binding(\.cornerRadius), in: 12...40)
                }
                Text("The top of the open notch stays black so it still meets the hardware.")
                    .font(theme.font(11)).foregroundStyle(.white.opacity(0.45))
            }
        }
        .foregroundStyle(.white)
    }

    private func binding(_ keyPath: WritableKeyPath<NotchAppearance.Theme, Double>) -> Binding<Double> {
        Binding(get: { appearance.theme[keyPath: keyPath] }, set: { value in
            var next = appearance.theme
            next[keyPath: keyPath] = value
            next.preset = .custom
            appearance.theme = next
        })
    }

    private func choiceButton(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(appearance.theme.font(11, weight: .semibold))
                .padding(.horizontal, 8).frame(height: 26)
                .background(Capsule().fill(on ? appearance.theme.accent : .white.opacity(0.1)))
                .foregroundStyle(on ? .black : .white)
        }
        .buttonStyle(PressableStyle(scale: 0.95))
    }

    private func labeled<Control: View>(_ title: String, value: String, theme: NotchAppearance.Theme, @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(theme.font(12, weight: .medium))
                Spacer()
                Text(value).font(theme.font(12)).foregroundStyle(.white.opacity(0.5))
            }
            control()
        }
    }
}
