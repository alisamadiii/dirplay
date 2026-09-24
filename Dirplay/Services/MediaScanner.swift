import Foundation

/// Scans the chosen root folder for `Music/` and `Video/` (case-insensitive)
/// and builds a tree that mirrors the on-disk structure exactly.
enum MediaScanner {
    static let audioExtensions: Set<String> = ["mp3", "m4a", "m4b", "aac", "wav", "flac", "aif", "aiff", "caf"]
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    static func scanLibrary(at root: URL) -> (music: MediaFolder?, video: MediaFolder?) {
        guard let children = directoryContents(of: root) else { return (nil, nil) }
        var music: MediaFolder?
        var video: MediaFolder?
        for child in children where isDirectory(child) {
            switch child.lastPathComponent.lowercased() {
            case "music", "musics":
                music = scanFolder(at: child, matching: audioExtensions)
            case "video", "videos":
                video = scanFolder(at: child, matching: videoExtensions)
            default:
                break
            }
        }
        return (music, video)
    }

    static func scanFolder(at url: URL, matching extensions: Set<String>) -> MediaFolder {
        var subfolders: [MediaFolder] = []
        var items: [MediaItem] = []
        for child in directoryContents(of: url) ?? [] {
            if isDirectory(child) {
                subfolders.append(scanFolder(at: child, matching: extensions))
            } else if extensions.contains(child.pathExtension.lowercased()) {
                items.append(MediaItem(url: child))
            }
        }
        subfolders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        items.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        return MediaFolder(url: url, name: url.lastPathComponent, subfolders: subfolders, items: items)
    }

    private static func directoryContents(of url: URL) -> [URL]? {
        try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}
