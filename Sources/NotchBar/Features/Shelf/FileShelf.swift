import AppKit
import UniformTypeIdentifiers

/// Files parked on the open notch. Off until the menu turns it on.
@MainActor
final class FileShelf: ObservableObject {
    struct Item: Identifiable, Equatable, Codable {
        var path: String
        var name: String
        var bookmark: Data
        var id: String { path }
    }

    static weak var current: FileShelf?

    @Published private(set) var isEnabled: Bool
    @Published private(set) var items: [Item] = []

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: "fileShelfEnabled")
        if let data = UserDefaults.standard.data(forKey: "fileShelfItems"),
           let saved = try? JSONDecoder().decode([Item].self, from: data) {
            items = saved
        }
    }

    func bind() { Self.current = self }

    func setEnabled(_ on: Bool) {
        isEnabled = on
        UserDefaults.standard.set(on, forKey: "fileShelfEnabled")
    }

    var showsBar: Bool { isEnabled && !items.isEmpty }

    func add(url: URL) {
        guard isEnabled else { return }
        let bookmark = (try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)) ?? Data()
        let item = Item(path: url.path, name: url.lastPathComponent, bookmark: bookmark)
        items.removeAll { $0.path == item.path }
        items.insert(item, at: 0)
        if items.count > 12 { items = Array(items.prefix(12)) }
        persist()
    }

    func remove(_ item: Item) {
        items.removeAll { $0.path == item.path }
        persist()
    }

    /// A URL the user can drag back out. A bookmark is used when one was stored.
    func resolve(_ item: Item) -> URL? {
        if !item.bookmark.isEmpty {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: item.bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) {
                _ = url.startAccessingSecurityScopedResource()
                return url
            }
        }
        guard FileManager.default.fileExists(atPath: item.path) else { return nil }
        return URL(fileURLWithPath: item.path)
    }

    /// Loads dropped file URLs without capturing the shelf in the provider callback.
    func receive(_ providers: [NSItemProvider]) -> Bool {
        guard isEnabled else { return false }
        Self.current = self
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { object, _ in
                guard let url = FileShelf.fileURL(from: object) else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { FileShelf.current?.add(url: url) }
                }
            }
        }
        return true
    }

    nonisolated static func fileURL(from object: Any?) -> URL? {
        if let url = object as? URL { return url }
        if let data = object as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        return nil
    }

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: "fileShelfItems")
    }
}
