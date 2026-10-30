import SwiftUI
import UIKit

struct ThumbnailView: View {
    let url: URL
    var sampleSeconds: TimeInterval = 0.5
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .overlay {
                        Image(systemName: "film")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
        .task(id: "\(url.path)|\(sampleSeconds)") {
            image = await Thumbnails.image(for: url, sampleSeconds: sampleSeconds)
        }
    }
}
