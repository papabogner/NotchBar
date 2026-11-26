import Foundation

/// Notch DJ's own defaults. This is not NotchBar's domain.
enum DJDefaults {
    nonisolated(unsafe) static let suite: UserDefaults = {
        // In the app bundle this is already the standard domain, and a suite named after the app's
        // own bundle identifier is an error. Only unbundled `swift run` builds need the suite.
        if Bundle.main.bundleIdentifier == "com.local.notchdj" { return .standard }
        return UserDefaults(suiteName: "com.local.notchdj") ?? .standard
    }()

    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let folder = base.appendingPathComponent("Notch DJ", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()
}
