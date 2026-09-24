import Foundation

/// A single playable file on disk. The filesystem is the source of truth —
/// nothing about this item is persisted anywhere.
struct MediaItem: Identifiable, Hashable {
    let url: URL

    var id: URL { url }

    var displayName: String {
        url.deletingPathExtension().lastPathComponent
    }
}
