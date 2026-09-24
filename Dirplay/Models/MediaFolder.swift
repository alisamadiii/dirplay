import Foundation

/// A folder on disk, mirrored exactly as the user organized it.
/// Subfolders stay nested — the library is never flattened.
struct MediaFolder: Identifiable, Hashable {
    let url: URL
    let name: String
    var subfolders: [MediaFolder]
    var items: [MediaItem]

    var id: URL { url }

    var isEmpty: Bool { subfolders.isEmpty && items.isEmpty }

    /// All items in this folder and every nested subfolder. Used only for search.
    var allItems: [MediaItem] {
        items + subfolders.flatMap(\.allItems)
    }

    var totalItemCount: Int {
        items.count + subfolders.reduce(0) { $0 + $1.totalItemCount }
    }
}
