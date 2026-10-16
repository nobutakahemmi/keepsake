import AVFoundation
import UIKit

enum Thumbnails {
    static func image(for url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 360)
        let duration = (try? await asset.load(.duration)) ?? .zero
        let seconds = CMTimeGetSeconds(duration)
        let sample = seconds.isFinite ? min(0.5, max(0, seconds / 2)) : 0
        let time = CMTime(seconds: sample, preferredTimescale: 600)
        do {
            let result = try await generator.image(at: time)
            return UIImage(cgImage: result.image)
        } catch {
            return nil
        }
    }
}
