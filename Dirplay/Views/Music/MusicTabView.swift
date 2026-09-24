import SwiftUI

struct MusicTabView: View {
    @Environment(LibraryViewModel.self) private var library

    var body: some View {
        NavigationStack {
            Group {
                if let root = library.musicRoot {
                    FolderListView(folder: root, isRoot: true)
                } else {
                    ContentUnavailableView {
                        Label("No Music Folder", systemImage: "folder.badge.questionmark")
                    } description: {
                        Text("Create a folder named “Music” inside your chosen folder, add songs to it, then rescan from Settings.")
                    }
                }
            }
            .navigationDestination(for: MediaFolder.self) { folder in
                FolderListView(folder: folder)
            }
        }
        .miniPlayerInset()
    }
}

/// Renders one level of the on-disk folder tree: subfolders first, then tracks.
/// The structure the user created in Files is mirrored exactly.
struct FolderListView: View {
    @Environment(LibraryViewModel.self) private var library
    @Environment(PlayerViewModel.self) private var player
    let folder: MediaFolder
    var isRoot = false
    @State private var searchText = ""

    var body: some View {
        List {
            if searchText.isEmpty {
                browseContent
            } else {
                searchResults
            }
        }
        .overlay {
            if folder.isEmpty && searchText.isEmpty {
                ContentUnavailableView {
                    Label("Empty Folder", systemImage: "music.note.list")
                } description: {
                    Text("Add audio files to this folder in the Files app, then rescan from Settings.")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search songs")
        .refreshable { library.rescan() }
        .navigationTitle(isRoot ? "Music" : folder.name)
    }

    @ViewBuilder private var browseContent: some View {
        if !folder.subfolders.isEmpty {
            Section {
                ForEach(folder.subfolders) { subfolder in
                    NavigationLink(value: subfolder) {
                        FolderRow(folder: subfolder)
                    }
                }
            }
        }
        if !folder.items.isEmpty {
            Section {
                ForEach(folder.items) { item in
                    TrackRow(item: item, context: folder.items)
                }
            }
        }
    }

    @ViewBuilder private var searchResults: some View {
        let matches = folder.allItems.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
        if matches.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            ForEach(matches) { item in
                TrackRow(item: item, context: matches)
            }
        }
    }
}

struct FolderRow: View {
    let folder: MediaFolder

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .lineLimit(1)
                Text("^[\(folder.totalItemCount) item](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
