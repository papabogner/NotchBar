import AppKit
import CryptoKit
import Darwin
import Foundation
import Security

/// Spotify Connect through the Web API. Off until the menu turns it on.
/// The user supplies their own Client ID. Tokens stay in the Keychain.
@MainActor
final class SpotifyConnect: ObservableObject {
    static let redirectURI = "http://127.0.0.1:47321/callback"
    static let spotifyBundle = "com.spotify.client"

    struct Device: Identifiable, Equatable {
        var id: String
        var name: String
        var type: String
        var isActive: Bool
        var volume: Int?
        var symbol: String {
            switch type {
            case "Computer": return "desktopcomputer"
            case "Speaker": return "hifispeaker.fill"
            case "Smartphone": return "iphone"
            case "Tablet", "CastAudio": return "ipad"
            case "TV", "AVR", "STB", "CastVideo", "GameConsole": return "tv"
            case "Automobile": return "car.fill"
            default: return "airplayaudio"
            }
        }
    }

    @Published private(set) var isEnabled = false
    @Published var clientID: String {
        didSet { UserDefaults.standard.set(clientID, forKey: "spotifyClientID") }
    }
    @Published private(set) var devices: [Device] = []
    @Published private(set) var remoteVolume: Int = 50
    @Published private(set) var status: String = ""
    @Published private(set) var isSignedIn = false

    private var accessToken = ""
    private var refreshToken = ""
    private var expiry = Date.distantPast
    private var timer: EfficientTimer?
    private var watching = false

    var activeDevice: Device? { devices.first { $0.isActive } }
    /// A speaker, phone, or other Connect target, rather than this Mac.
    var controlsRemote: Bool {
        guard let active = activeDevice else { return false }
        return active.type != "Computer"
    }

    init() {
        clientID = UserDefaults.standard.string(forKey: "spotifyClientID") ?? ""
        isEnabled = UserDefaults.standard.bool(forKey: "spotifyConnectEnabled")
        if let saved = SpotifyKeychain.load() {
            accessToken = saved.access
            refreshToken = saved.refresh
            expiry = saved.expiry
            isSignedIn = !accessToken.isEmpty && !refreshToken.isEmpty
        }
    }

    func setEnabled(_ on: Bool) {
        isEnabled = on
        UserDefaults.standard.set(on, forKey: "spotifyConnectEnabled")
        if on {
            refreshDevices()
            updateTimer()
        } else {
            timer?.stop()
            devices = []
        }
    }

    /// Poll only while the notch is open and the feature is on.
    func setWatching(_ on: Bool) {
        watching = on
        updateTimer()
        if on && isEnabled { refreshDevices() }
    }

    func signOut() {
        accessToken = ""
        refreshToken = ""
        expiry = .distantPast
        isSignedIn = false
        devices = []
        status = "Signed out."
        SpotifyKeychain.clear()
    }

    func signIn() {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { status = "Paste your Spotify Client ID first."; return }
        clientID = id
        let verifier = Self.verifier()
        let state = UUID().uuidString
        guard let url = Self.authorizeURL(clientID: id, verifier: verifier, state: state) else {
            status = "Couldn't build the Spotify sign-in link."
            return
        }
        status = "Waiting for Spotify in the browser…"
        Task { @MainActor [weak self] in
            let result = await Task.detached { () -> Result<String, String> in
                SpotifyLoopback.waitForCode(open: url, state: state, timeout: 180)
            }.value
            guard let self else { return }
            switch result {
            case .failure(let message):
                self.status = message
            case .success(let code):
                await self.exchange(code: code, verifier: verifier)
            }
        }
    }

    func refreshDevices() {
        guard isEnabled, isSignedIn else { return }
        Task { @MainActor [weak self] in
            guard let self, let token = await self.validToken() else { return }
            await self.loadDevices(token: token)
        }
    }

    func transfer(to device: Device) {
        guard isEnabled else { return }
        Task { @MainActor [weak self] in
            guard let self, let token = await self.validToken() else { return }
            let body: [String: Any] = ["device_ids": [device.id], "play": true]
            let outcome = await Self.send("PUT", path: "/v1/me/player", token: token, json: body)
            if case .premium = outcome {
                self.status = "Spotify Connect needs a Premium account."
                return
            }
            if case .failed(let message) = outcome {
                self.status = message
                return
            }
            self.status = "Playing on \(device.name)"
            await self.loadDevices(token: token)
        }
    }

    func setRemoteVolume(_ percent: Int) {
        let clamped = min(100, max(0, percent))
        remoteVolume = clamped
        guard controlsRemote, let id = activeDevice?.id else { return }
        Task { @MainActor [weak self] in
            guard let self, let token = await self.validToken() else { return }
            var parts = URLComponents()
            parts.queryItems = [
                URLQueryItem(name: "volume_percent", value: "\(clamped)"),
                URLQueryItem(name: "device_id", value: id),
            ]
            let path = "/v1/me/player/volume?\(parts.percentEncodedQuery ?? "")"
            let outcome = await Self.send("PUT", path: path, token: token, json: nil)
            if case .premium = outcome { self.status = "Spotify Connect needs a Premium account." }
        }
    }

    private func updateTimer() {
        let should = isEnabled && isSignedIn && watching
        if should {
            if timer == nil {
                timer = EfficientTimer(interval: 20, tolerance: 5) { [weak self] in
                    MainActor.assumeIsolated { self?.refreshDevices() }
                }
            }
            timer?.start()
        } else {
            timer?.stop()
        }
    }

    private func exchange(code: String, verifier: String) async {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let fields = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ]
        request.httpBody = Self.form(fields).data(using: .utf8)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            status = "Couldn't reach Spotify."
            return
        }
        guard http.statusCode == 200, let saved = Self.parseToken(data, previousRefresh: "") else {
            status = "Spotify didn't accept the sign-in."
            return
        }
        store(saved)
        status = "Signed in."
        await loadDevices(token: saved.access)
        updateTimer()
    }

    private func validToken() async -> String? {
        if expiry.timeIntervalSinceNow > 60, !accessToken.isEmpty { return accessToken }
        guard !refreshToken.isEmpty else { status = "Sign in to Spotify again."; return nil }
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ]).data(using: .utf8)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let saved = Self.parseToken(data, previousRefresh: refreshToken) else {
            status = "Spotify sign-in expired. Sign in again."
            return nil
        }
        store(saved)
        return saved.access
    }

    private func loadDevices(token: String) async {
        let outcome = await Self.send("GET", path: "/v1/me/player/devices", token: token, json: nil)
        switch outcome {
        case .premium:
            status = "Spotify Connect needs a Premium account."
        case .failed(let message):
            status = message
        case .data(let data):
            devices = Self.parseDevices(data)
            if let volume = activeDevice?.volume { remoteVolume = volume }
            if status == "Spotify Connect needs a Premium account." { status = "" }
        case .empty:
            devices = []
        }
    }

    private func store(_ saved: SpotifyKeychain.Token) {
        accessToken = saved.access
        refreshToken = saved.refresh
        expiry = saved.expiry
        isSignedIn = true
        SpotifyKeychain.save(saved)
    }

    private enum Call {
        case data(Data)
        case empty
        case premium
        case failed(String)
    }

    private static func send(_ method: String, path: String, token: String, json: [String: Any]?) async -> Call {
        guard let url = URL(string: "https://api.spotify.com" + path) else { return .failed("Bad Spotify request.") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: json)
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return .failed("Couldn't reach Spotify.") }
        if http.statusCode == 204 || data.isEmpty { return .empty }
        if http.statusCode == 403 { return .premium }
        if http.statusCode == 401 { return .failed("Spotify sign-in expired. Sign in again.") }
        guard (200..<300).contains(http.statusCode) else { return .failed("Spotify returned \(http.statusCode).") }
        return .data(data)
    }

    private static func parseDevices(_ data: Data) -> [Device] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["devices"] as? [[String: Any]] else { return [] }
        return list.compactMap { item in
            guard let id = item["id"] as? String, let name = item["name"] as? String else { return nil }
            return Device(id: id, name: name, type: item["type"] as? String ?? "",
                          isActive: item["is_active"] as? Bool ?? false,
                          volume: item["volume_percent"] as? Int)
        }
    }

    private static func parseToken(_ data: Data, previousRefresh: String) -> SpotifyKeychain.Token? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = root["access_token"] as? String else { return nil }
        let refresh = (root["refresh_token"] as? String) ?? previousRefresh
        guard !refresh.isEmpty else { return nil }
        let expires = root["expires_in"] as? Double ?? 3600
        return SpotifyKeychain.Token(access: access, refresh: refresh, expiry: Date().addingTimeInterval(expires))
    }

    private static func form(_ fields: [String: String]) -> String {
        fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)"
        }.joined(separator: "&")
    }

    private static func verifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func authorizeURL(clientID: String, verifier: String, state: String) -> URL? {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var parts = URLComponents(string: "https://accounts.spotify.com/authorize")
        parts?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: "user-read-playback-state user-modify-playback-state"),
        ]
        return parts?.url
    }
}

enum SpotifyKeychain {
    struct Token: Equatable {
        var access: String
        var refresh: String
        var expiry: Date
    }

    private static let service = "com.local.notchbar.spotify"
    private static let account = "tokens"

    static func save(_ token: Token) {
        let payload: [String: String] = [
            "access": token.access,
            "refresh": token.refresh,
            "expiry": String(token.expiry.timeIntervalSince1970),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        clear()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> Token? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let access = root["access"], let refresh = root["refresh"],
              let expiry = Double(root["expiry"] ?? "") else { return nil }
        return Token(access: access, refresh: refresh, expiry: Date(timeIntervalSince1970: expiry))
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// One-shot loopback so Spotify can redirect without a custom URL scheme.
enum SpotifyLoopback {
    nonisolated static let port: UInt16 = 47321

    nonisolated static func waitForCode(open url: URL, state: String, timeout: TimeInterval) -> Result<String, String> {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return .failure("Couldn't open a local port.") }
        defer { close(fd) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, Darwin.listen(fd, 1) == 0 else {
            return .failure("Port 47321 is in use. Free it and sign in again.")
        }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { NSWorkspace.shared.open(url) }
        }
        var waiting = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        guard poll(&waiting, 1, Int32(timeout * 1000)) > 0 else {
            return .failure("Spotify didn't return. Try signing in again.")
        }
        let client = accept(fd, nil, nil)
        guard client >= 0 else { return .failure("Spotify didn't return.") }
        defer { close(client) }
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = read(client, &buffer, buffer.count)
        let text = String(decoding: buffer.prefix(max(0, count)), as: UTF8.self)
        let page = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n<html><body><p>NotchBar is signed in. You can close this tab.</p></body></html>"
        _ = page.withCString { write(client, $0, strlen($0)) }
        guard let code = query("code", in: text), query("state", in: text) == state else {
            return .failure(text.contains("error=") ? "Spotify declined the sign-in." : "Spotify didn't return a code.")
        }
        return .success(code)
    }

    private nonisolated static func query(_ name: String, in header: String) -> String? {
        guard let lineEnd = header.range(of: "\r\n") else { return nil }
        let request = header[..<lineEnd.lowerBound]
        guard let pathStart = request.range(of: " ")?.upperBound,
              let pathEnd = request[pathStart...].range(of: " ")?.lowerBound else { return nil }
        let path = String(request[pathStart..<pathEnd])
        guard let components = URLComponents(string: "http://127.0.0.1" + path) else { return nil }
        return components.queryItems?.first { $0.name == name }?.value
    }
}

