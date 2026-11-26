import AppKit
import SwiftUI

struct DJRootView: View {
    @ObservedObject var model: DJModel

    var body: some View {
        VStack(spacing: 0) {
            notch
            Spacer(minLength: 0)
        }
        .frame(width: DJWindow.canvas.width, height: DJWindow.canvas.height, alignment: .top)
        .preferredColorScheme(.dark)
    }

    private var notch: some View {
        let size = model.size
        return ZStack(alignment: .top) {
            if model.isExpanded {
                expanded
                    .frame(width: model.expandedSize.width, height: model.expandedSize.height, alignment: .top)
            } else {
                collapsed
                    .frame(width: size.width, height: size.height, alignment: .top)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(Color.black)
        .clipShape(NotchShape(topRadius: model.topRadius, bottomRadius: model.bottomRadius))
        .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
        .environment(\.notchChrome, DJChrome())
        .contentShape(NotchShape(topRadius: model.topRadius, bottomRadius: model.bottomRadius))
        .offset(x: model.shapeOffset)
    }

    private var collapsed: some View {
        HStack(spacing: 0) {
            if let entry = model.now.entry, entry.isPlaying {
                Text("\(entry.title) · \(entry.artist)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(width: model.leftWing, alignment: .trailing)
                    .padding(.trailing, 8)
            }
            Color.clear
                .frame(width: model.geometry.notchWidth, height: model.geometry.notchHeight)
                .contentShape(Rectangle())
                .onTapGesture { model.toggle() }
        }
        .frame(height: model.geometry.notchHeight)
    }

    private var expanded: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: model.geometry.notchHeight)
                .contentShape(Rectangle())
                .onTapGesture { model.close() }
            MixerPanel(mixer: model.mixer,
                       highlight: model.now.entry?.source.bundleID,
                       nowTitle: model.now.entry?.title,
                       nowArtist: model.now.entry?.artist,
                       nowBundle: model.now.entry?.source.bundleID,
                       artwork: model.now.artwork)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }
}
