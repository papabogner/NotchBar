import SwiftUI

/// Client ID and sign-in for Spotify Connect. Opened from the … menu.
struct SpotifyConnectPanel: View {
    @ObservedObject var spotify: SpotifyConnect
    var close: () -> Void
    @FocusState private var clientFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Spotify Connect").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Done", action: close).buttonStyle(PressableStyle(scale: 0.96))
                    .font(.system(size: 12, weight: .semibold))
            }
            Text("Create a Spotify app and set the redirect URI to exactly")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            Text(SpotifyConnect.redirectURI)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .textSelection(.enabled)
            HStack(spacing: 8) {
                TextField("Client ID", text: $spotify.clientID)
                    .textFieldStyle(.roundedBorder)
                    .focused($clientFocused)
                Button("Paste from Clipboard") { spotify.pasteClientID() }
                    .buttonStyle(PressableStyle(scale: 0.96))
            }
            .font(.system(size: 12, weight: .semibold))
            .onAppear { clientFocused = true }
            HStack(spacing: 8) {
                Button(spotify.isSignedIn ? "Sign in again" : "Sign in") { spotify.signIn() }
                    .buttonStyle(PressableStyle(scale: 0.96))
                if spotify.isSignedIn {
                    Button("Sign out") { spotify.signOut() }
                        .buttonStyle(PressableStyle(scale: 0.96))
                }
            }
            .font(.system(size: 12, weight: .semibold))
            if !spotify.status.isEmpty {
                Text(spotify.status).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Devices for the Spotify strip and Now Playing. Hidden unless Connect is turned on.
struct SpotifyDeviceMenu: View {
    @ObservedObject var spotify: SpotifyConnect

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Menu {
                if spotify.devices.isEmpty {
                    Button("No devices") {}.disabled(true)
                }
                ForEach(spotify.devices) { device in
                    Button {
                        spotify.transfer(to: device)
                    } label: {
                        Label(device.isActive ? "\(device.name) · playing" : device.name, systemImage: device.symbol)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: spotify.activeDevice?.symbol ?? "airplayaudio")
                    Text(spotify.activeDevice?.name ?? "Connect")
                        .lineLimit(1)
                }
                .font(.system(size: 11, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            if spotify.controlsRemote {
                Slider(value: Binding(get: { Double(spotify.remoteVolume) }, set: { spotify.setRemoteVolume(Int($0)) }),
                       in: 0...100, step: 1)
                    .controlSize(.small)
            }
            if spotify.status == "Spotify Connect needs a Premium account." {
                Text(spotify.status).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
            }
        }
    }
}
