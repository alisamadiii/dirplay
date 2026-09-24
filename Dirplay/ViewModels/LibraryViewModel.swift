import Foundation
import Observation

@Observable @MainActor
final class LibraryViewModel {
    enum State {
        case needsFolder
        case loading
        case loaded
    }

    private(set) var state: State
    private(set) var rootURL: URL?
    private(set) var musicRoot: MediaFolder?
    private(set) var videoRoot: MediaFolder?
    /// Bumped when a file's on-disk metadata changes so rows reload their tags.
    private(set) var metadataRevision = 0

    init() {
        state = FolderAccessManager.hasBookmark ? .loading : .needsFolder
    }

    /// Resolves the saved bookmark on launch. Falls back to the welcome
    /// screen if the folder no longer exists or access was lost.
    func restore() {
        guard rootURL == nil else { return }
        guard let url = FolderAccessManager.restoreRootURL() else {
            state = .needsFolder
            return
        }
        rootURL = url
        rescan()
    }

    /// Called with the URL from the folder picker.
    func setRoot(_ url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        FolderAccessManager.saveBookmark(for: url)
        rootURL = url
        rescan()
    }

    func noteMetadataChanged(for url: URL) {
        MetadataLoader.shared.invalidate(for: url)
        metadataRevision += 1
    }

    func rescan() {
        guard let rootURL else { return }
        state = .loading
        Task.detached(priority: .userInitiated) { [rootURL] in
            let result = MediaScanner.scanLibrary(at: rootURL)
            await MainActor.run {
                self.musicRoot = result.music
                self.videoRoot = result.video
                self.state = .loaded
            }
        }
    }
}
