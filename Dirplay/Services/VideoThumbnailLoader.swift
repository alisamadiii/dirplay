import AVFoundation
import UIKit

/// Generates and caches small poster frames for video list rows. In-memory
/// cache only — nothing is written to disk.
final class VideoThumbnailLoader {
    static let shared = VideoThumbnailLoader()

    private let cache = NSCache<NSURL, UIImage>()

    func thumbnail(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        // A loose tolerance lets the generator grab the nearest keyframe,
        // which is far cheaper than exact decoding.
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        guard let duration = try? await asset.load(.duration), duration.seconds.isFinite else {
            return nil
        }
        // A frame slightly into the video: black lead-ins are common at 0:00.
        let target = CMTime(seconds: min(1, duration.seconds * 0.1), preferredTimescale: 600)
        guard let (cgImage, _) = try? await generator.image(at: target) else {
            return nil
        }
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
