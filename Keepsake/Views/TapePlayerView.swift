import AVKit
import SwiftUI

struct TapePlayerView: View {
    let url: URL
    let title: String
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .accessibilityLabel(title)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                guard player == nil else { return }
                let created = AVPlayer(url: url)
                player = created
                created.play()
            }
            .onDisappear {
                player?.pause()
            }
    }
}
