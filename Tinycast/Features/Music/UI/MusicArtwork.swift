import SwiftUI

struct MusicArtwork: View {
    var data: Data?
    var size: CGFloat
    var symbol = "music.note"
    var symbolSize: CGFloat?
    var symbolColor = Theme.Colors.textTertiary

    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(Theme.Colors.controlSurface)
                    .overlay {
                        SymbolImage(name: symbol, size: symbolSize ?? size / 2, monochrome: true)
                            .foregroundStyle(symbolColor)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous))
        .accessibilityHidden(true)
    }
}
