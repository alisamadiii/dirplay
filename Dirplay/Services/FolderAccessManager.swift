import Foundation

/// Persists access to the user-chosen root folder via a security-scoped bookmark.
/// This is the only thing Dirplay stores besides small UI preferences — no database.
enum FolderAccessManager {
    private static let bookmarkKey = "rootFolderBookmark"

    static var hasBookmark: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    static func saveBookmark(for url: URL) {
        guard let data = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    /// Resolves the stored bookmark and begins security-scoped access.
    /// Returns nil if the folder was deleted, moved out of reach, or access was revoked.
    static func restoreRootURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        // A picker-issued bookmark needs scoped access; fall back to a plain
        // reachability check so non-scoped bookmarks (e.g. in development)
        // still resolve.
        if !url.startAccessingSecurityScopedResource(),
           (try? url.checkResourceIsReachable()) != true {
            return nil
        }
        if isStale {
            saveBookmark(for: url)
        }
        return url
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }
}
