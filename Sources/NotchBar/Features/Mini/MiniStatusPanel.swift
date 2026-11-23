import SwiftUI

/// Host alias for the other Mac. The default matches a ~/.ssh/config Host.
struct MiniStatusPanel: View {
    @ObservedObject var mini: MiniStatus
    var close: () -> Void
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mac mini").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Done") {
                    mini.setHost(draft)
                    close()
                }
                .buttonStyle(PressableStyle(scale: 0.96))
                .font(.system(size: 12, weight: .semibold))
            }
            Text("An SSH alias from ~/.ssh/config. NotchBar uses BatchMode, so it never asks for a password.")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            TextField("Host", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onAppear { draft = mini.host }
            if mini.isEnabled {
                Text(mini.report.online ? mini.line : "\(mini.host) is offline")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                if !mini.report.top.isEmpty {
                    Text(mini.report.top).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
