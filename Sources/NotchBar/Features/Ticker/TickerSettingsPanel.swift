import SwiftUI

/// Width, pace, a custom line, and an optional feed URL for the closed-notch ticker.
struct TickerSettingsPanel: View {
    @ObservedObject var ticker: TickerStore
    var close: () -> Void
    @FocusState private var lineFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ticker").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Done", action: close).buttonStyle(PressableStyle(scale: 0.96))
                    .font(.system(size: 12, weight: .semibold))
            }
            Text("Off until Show Ticker is on. It hides when the menu bar is hidden.")
                .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.55))
            labeled("Width", value: "\(Int(ticker.width))") {
                Slider(value: $ticker.width, in: 120...280, step: 20)
            }
            labeled("Every", value: "\(Int(ticker.interval))s") {
                Slider(value: $ticker.interval, in: 4...30, step: 1)
            }
            TextField("Custom line", text: $ticker.customText)
                .textFieldStyle(.roundedBorder)
                .focused($lineFocused)
                .onAppear { lineFocused = true }
            TextField("Feed URL (JSON or RSS)", text: $ticker.feedURL)
                .textFieldStyle(.roundedBorder)
            Text("Crypto uses CoinGecko for BTC, ETH, SOL, and ADA in euros. A feed that fails is skipped.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func labeled<Control: View>(_ title: String, value: String, @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(value).font(.system(size: 12, design: .rounded).monospacedDigit()).foregroundStyle(.white.opacity(0.55))
            }
            control()
        }
    }
}
