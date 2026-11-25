import SwiftUI
import UniformTypeIdentifiers

/// The parked files along the bottom of the open notch.
struct FileShelfBar: View {
    @ObservedObject var shelf: FileShelf

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(shelf.items) { item in
                    chip(item)
                }
            }
        }
        .frame(height: 28)
    }

    private func chip(_ item: FileShelf.Item) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "doc").font(.system(size: 10, weight: .semibold))
            Text(item.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
            Button { shelf.remove(item) } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(PressableStyle(scale: 0.9))
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Capsule().fill(.white.opacity(0.1)))
        .onDrag {
            guard let url = shelf.resolve(item) else { return NSItemProvider() }
            return NSItemProvider(object: url as NSURL)
        }
        .onTapGesture {
            guard let url = shelf.resolve(item) else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        .help(item.name)
    }
}
