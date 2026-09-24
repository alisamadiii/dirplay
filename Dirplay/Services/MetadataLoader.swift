import AVFoundation
import Foundation

struct TrackMetadata {
    var title: String?
    var artist: String?
    var album: String?
    var artworkData: Data?
    var duration: TimeInterval?
}

/// Reads ID3/MP4 metadata straight from the files. Results are kept in an
/// in-memory cache only — nothing is written to disk.
final class MetadataLoader {
    static let shared = MetadataLoader()

    private final class Box {
        let value: TrackMetadata
        init(_ value: TrackMetadata) { self.value = value }
    }

    private let cache = NSCache<NSURL, Box>()

    /// Call after a file's tags change on disk (e.g. artwork embedded).
    func invalidate(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }

    func metadata(for url: URL) async -> TrackMetadata {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached.value
        }
        let asset = AVURLAsset(url: url)
        var result = TrackMetadata()
        if let duration = try? await asset.load(.duration), duration.seconds.isFinite {
            result.duration = duration.seconds
        }
        if let commonMetadata = try? await asset.load(.commonMetadata) {
            for item in commonMetadata {
                switch item.commonKey {
                case .commonKeyTitle?:
                    if let value = try? await item.load(.stringValue) { result.title = value }
                case .commonKeyArtist?:
                    if let value = try? await item.load(.stringValue) { result.artist = value }
                case .commonKeyAlbumName?:
                    if let value = try? await item.load(.stringValue) { result.album = value }
                case .commonKeyArtwork?:
                    if let value = try? await item.load(.dataValue) { result.artworkData = value }
                default:
                    break
                }
            }
        }
        cache.setObject(Box(result), forKey: url as NSURL)
        return result
    }
}
