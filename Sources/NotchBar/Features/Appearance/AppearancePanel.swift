import SwiftUI

/// Presets and color controls for the notch. Opened from the … menu.
struct AppearancePanel: View {
    @ObservedObject var appearance: NotchAppearance
    var close: () -> Void

    var body: some View {
        let theme = appearance.theme
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Appearance").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Done", action: close).buttonStyle(PressableStyle(scale: 0.96))
                    .font(.system(size: 12, weight: .semibold))
            }
            HStack(spacing: 8) {
                ForEach(NotchAppearance.Theme.Preset.allCases) { preset in
                    Button { appearance.apply(preset) } label: {
                        Text(preset.title).font(.system(size: 11.5, weight: .semibold))
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(Capsule().fill(theme.preset == preset ? .white : .white.opacity(0.1)))
                            .foregroundStyle(theme.preset == preset ? .black : .white)
                    }
                    .buttonStyle(PressableStyle(scale: 0.95))
                }
            }
            Toggle("Album colors", isOn: Binding(get: { appearance.theme.albumColors }, set: { value in
                var next = appearance.theme
                next.albumColors = value
                next.preset = .custom
                appearance.theme = next
            }))
            .toggleStyle(.switch)
            .font(.system(size: 12, weight: .medium))
            HStack(spacing: 16) {
                ColorPicker("Accent", selection: Binding(get: { theme.accent }, set: { appearance.setAccent($0) }), supportsOpacity: false)
                ColorPicker("Background", selection: Binding(get: { theme.background }, set: { appearance.setBackground($0, end: false) }), supportsOpacity: false)
                ColorPicker("Gradient", selection: Binding(get: { theme.backgroundEnd }, set: { appearance.setBackground($0, end: true) }), supportsOpacity: false)
            }
            .font(.system(size: 12))
            HStack {
                Text("Angle").font(.system(size: 12))
                Slider(value: Binding(get: { appearance.theme.angle }, set: { value in
                    var next = appearance.theme
                    next.angle = value
                    next.preset = .custom
                    appearance.theme = next
                }), in: 0...360)
            }
            Text("The closed notch stays black so it matches the hardware.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
        }
        .foregroundStyle(.white)
    }
}
