import Foundation

/// Notch DJ's own defaults. This is not NotchBar's domain.
enum DJDefaults {
    static let suite: UserDefaults = {
        UserDefaults(suiteName: "com.local.notchdj") ?? .standard
    }()

    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let folder = base.appendingPathComponent("Notch DJ", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()
}
