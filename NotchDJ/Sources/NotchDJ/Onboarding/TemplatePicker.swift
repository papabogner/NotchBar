import SwiftUI

/// The templates as cards. Used by onboarding and Settings › Appearance.
struct TemplateGrid: View {
    @EnvironmentObject private var prefs: DJPreferences
    var columns = 1

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(TemplateID.allCases) { id in
                TemplateCard(id: id, selected: prefs.template == id) {
                    withAnimation(Motion.step) { prefs.template = id }
                }
            }
        }
    }
}

struct TemplateCard: View {
    let id: TemplateID
    let selected: Bool
    let action: @MainActor () -> Void

    @EnvironmentObject private var prefs: DJPreferences
    @Environment(\.djTokens) private var chrome

    var body: some View {
        let tokens = prefs.tokens(for: id)
        let template = id.template
        Button {
            action()
        } label: {
            HStack(spacing: 10) {
                swatch(tokens)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: template.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(verbatim: template.blurb)
                        .font(.system(size: 11))
                        .foregroundStyle(chrome.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(chrome.accent)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? chrome.accent.opacity(0.14) : chrome.surface))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? chrome.accent : chrome.line, lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The template's panel, accent and deck colors.
    private func swatch(_ tokens: ThemeTokens) -> some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tokens.panel)
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(tokens.line, lineWidth: 1))
            HStack(spacing: 3) {
                Circle().fill(tokens.deckA).frame(width: 8, height: 8)
                Circle().fill(tokens.deckB).frame(width: 8, height: 8)
                Capsule().fill(tokens.accent).frame(width: 14, height: 8)
            }
            .padding(5)
        }
        .frame(width: 52, height: 36)
    }
}

/// The DJ tab of a template, running on sample data with moving meters. Not interactive.
struct TemplatePreview: View {
    let id: TemplateID
    var width: CGFloat = 380

    @EnvironmentObject private var prefs: DJPreferences
    @StateObject private var stage = PreviewStage()

    var body: some View {
        let tokens = prefs.tokens(for: id)
        let metrics = PanelMetrics.make(.regular)
        let size = CGSize(width: metrics.width, height: metrics.height - metrics.header)
        let scale = width / size.width
        id.template.makeDJView()
            .padding(.horizontal, metrics.padding + NotchStyle.openTop)
            .padding(.vertical, metrics.padding)
            .frame(width: size.width, height: size.height)
            .background(tokens.panel)
            .foregroundStyle(tokens.text)
            .environment(\.djTokens, tokens)
            .environment(\.panelMetrics, metrics)
            .environment(\.colorScheme, tokens.isDark ? .dark : .light)
            .environment(\.metersLive, true)
            .environmentObject(stage.model)
            .environmentObject(stage.mixer)
            .environmentObject(stage.now)
            .environmentObject(stage.prefs)
            .environmentObject(stage.permissions)
            .clipShape(RoundedRectangle(cornerRadius: tokens.panelRadius, style: .continuous))
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
            .allowsHitTesting(false)
            .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Preview of \(id.template.name)"))
    }
}
