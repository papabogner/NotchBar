import SwiftUI

/// The band beside the notch: tabs on the left, template picker and Settings on the right.
/// A click on the notch itself closes the panel.
struct PanelTopBar: View {
    @EnvironmentObject private var model: DJModel
    @Environment(\.djTokens) private var tokens
    @Environment(\.panelMetrics) private var metrics
    @Namespace private var tabs

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(PanelTab.allCases) { tab in
                    tabButton(tab)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear
                .frame(width: model.geometry.hasNotch ? model.geometry.notchWidth + 16 : 24)
                .contentShape(Rectangle())
                .onTapGesture { model.close() }
                .accessibilityLabel(Text("Close"))
                .accessibilityAddTraits(.isButton)
            HStack(spacing: 4) {
                TemplateMenu()
                IconButton(systemName: "gearshape", help: String(localized: "Settings")) { model.showSettings() }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, NotchStyle.openTop + metrics.padding * 0.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tokens.header)
        .foregroundStyle(tokens.headerText)
        .contextMenu { PanelMenuItems() }
    }

    private func tabButton(_ tab: PanelTab) -> some View {
        let selected = model.tab == tab
        return Button {
            model.select(tab)
        } label: {
            Text(tab.title)
                .font(.system(size: 11, weight: .semibold, design: tokens.textDesign))
                .tracking(0.8)
                .foregroundStyle(selected ? tokens.onAccent : tokens.headerText.opacity(0.62))
                .padding(.horizontal, 11)
                .frame(height: max(18, min(22, metrics.header - 10)))
                .background {
                    if selected {
                        Capsule()
                            .fill(tokens.accent)
                            .matchedGeometryEffect(id: "tab", in: tabs)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Quick switch for template, appearance and size.
struct TemplateMenu: View {
    @EnvironmentObject private var prefs: DJPreferences

    var body: some View {
        let current = prefs.template.template
        Menu {
            Picker("Template", selection: $prefs.template) {
                ForEach(TemplateID.allCases) { id in
                    Text(id.template.name).tag(id)
                }
            }
            .pickerStyle(.inline)
            if current.supportsLight && current.supportsDark {
                Picker("Appearance", selection: $prefs.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.inline)
            }
            Picker("Size", selection: $prefs.panelSize) {
                ForEach(PanelSize.allCases) { size in
                    Text(size.title).tag(size)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "paintpalette")
                Text(current.name)
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 6)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text("Template"))
    }
}

/// A small symbol button.
struct IconButton: View {
    let systemName: String
    let help: String
    var size: CGFloat = 13
    var active = false
    let action: @MainActor () -> Void

    @Environment(\.djTokens) private var tokens

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(active ? AnyShapeStyle(tokens.accent) : AnyShapeStyle(HierarchicalShapeStyle.primary))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
