import SwiftUI

/// Minimal in v1 by design — mirrors the Video folder structure and plays
/// files with the system player. Polish comes later.
struct VideoTabView: View {
    @Environment(LibraryViewModel.self) private var library
    @State private var selectedVideo: MediaItem?

    var body: some View {
        NavigationStack {
            Group {
                if let root = library.videoRoot {
                    VideoFolderListView(folder: root, isRoot: true, selectedVideo: $selectedVideo)
                } else {
                    ContentUnavailableView {
                        Label("No Video Folder", systemImage: "folder.badge.questionmark")
                    } description: {
                        Text("Create a folder named “Video” inside your chosen folder, add videos to it, then rescan from Settings.")
                    }
                }
            }
            .navigationDestination(for: MediaFolder.self) { folder in
                VideoFolderListView(folder: folder, selectedVideo: $selectedVideo)
            }
        }
        .fullScreenCover(item: $selectedVideo) { item in
            VideoPlayerScreen(item: item)
        }
        .miniPlayerInset()
    }
}

struct VideoFolderListView: View {
    @Environment(LibraryViewModel.self) private var library
    let folder: MediaFolder
    var isRoot = false
    @Binding var selectedVideo: MediaItem?

    var body: some View {
        List {
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
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selectedVideo = item
                        } label: {
                            VideoRow(item: item)
                        }
                    }
                }
            }
        }
        .overlay {
            if folder.isEmpty {
                ContentUnavailableView {
                    Label("Empty Folder", systemImage: "film.stack")
                } description: {
                    Text("Add video files to this folder in the Files app, then rescan from Settings.")
                }
            }
        }
        .refreshable { library.rescan() }
        .navigationTitle(isRoot ? "Video" : folder.name)
    }
}

/// List row with a real poster-frame thumbnail; falls back to the gray
/// placeholder while loading or when generation fails.
struct VideoRow: View {
    let item: MediaItem
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.tertiarySystemFill))
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    Image(systemName: "play.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 60, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .animation(.easeInOut(duration: 0.2), value: thumbnail == nil)
            Text(item.displayName)
                .lineLimit(2)
                .foregroundStyle(Color.primary)
        }
        .task(id: item.url) {
            thumbnail = await VideoThumbnailLoader.shared.thumbnail(for: item.url)
        }
    }
}
