// Based on NotchBar (https://github.com/srisanthosh/NotchBar), GPLv3.
// Original copyright remains with the NotchBar authors. Notch DJ changes are under the same license.
import AppKit
import SwiftUI

/// Short names for strips and cards.
enum MixerDisplayName {
    static func short(bundleID: String, fallback: String) -> String {
        if let known = known[bundleID] { return known }
        var name = fallback
        for prefix in ["Google ", "Mozilla ", "Apple "] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
        }
        let helper = " Helper"
        if name.hasSuffix(helper) { name.removeLast(helper.count) }
        return name
    }

    private static let known: [String: String] = [
        "com.google.Chrome": "Chrome",
        "com.google.Chrome.beta": "Chrome",
        "com.apple.Safari": "Safari",
        "com.apple.SafariTechnologyPreview": "Safari",
        "com.spotify.client": "Spotify",
        "com.apple.Music": "Music",
        "com.apple.finder": "Finder",
        "com.microsoft.edgemac": "Edge",
        "com.brave.Browser": "Brave",
        "company.thebrowser.Browser": "Arc",
        "com.apple.dt.Xcode": "Xcode",
        "com.apple.Terminal": "Terminal",
        "com.apple.FaceTime": "FaceTime",
        "us.zoom.xos": "Zoom",
        "com.microsoft.teams": "Teams",
        "com.microsoft.teams2": "Teams",
        "com.cisco.webexmeetingsapp": "Webex",
        "com.apple.podcasts": "Podcasts",
        "com.apple.TV": "TV",
        "com.apple.QuickTimePlayerX": "QuickTime",
        "com.apple.mail": "Mail",
        "org.mozilla.firefox": "Firefox",
        "com.tinyspeck.slackmacgap": "Slack",
        "com.hnc.Discord": "Discord",
        "com.openai.chat": "ChatGPT",
        "com.anthropic.claudefordesktop": "Claude",
        "com.todesktop.230313mzl4w4u92": "Cursor",
    ]
}

/// App icons, loaded once per bundle ID.
@MainActor
enum MixerIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String) -> NSImage? {
        if let cached = cache[bundleID] { return cached }
        guard let icon = MediaSource.forBundle(bundleID).icon else { return nil }
        icon.size = NSSize(width: 64, height: 64)
        cache[bundleID] = icon
        return icon
    }
}

/// An app's icon, or a neutral square when there is none.
struct AppIconView: View {
    let bundleID: String?
    var size: CGFloat = 22

    @Environment(\.djTokens) private var tokens

    var body: some View {
        Group {
            if let bundleID, let icon = MixerIcons.icon(for: bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(tokens.raised)
                    .overlay(
                        Image(systemName: "app.dashed")
                            .font(.system(size: size * 0.5))
                            .foregroundStyle(tokens.tertiary)
                    )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
