import SwiftUI

struct TrackRow: View {
    @Environment(PlayerViewModel.self) private var player
    @Environment(LibraryViewModel.self) private var library
    let item: MediaItem
    /// The tracks that become the queue when this row is tapped.
    let context: [MediaItem]
    @State private var metadata: TrackMetadata?
    @State private var isPickingArtwork = false

    private var isCurrent: Bool { player.current == item }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(duration: 0.35)) {
                player.play(item, in: context)
            }
        } label: {
            HStack(spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(metadata?.title ?? item.displayName)
                        .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                        .lineLimit(1)
                    if let artist = metadata?.artist {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if isCurrent && player.isPlaying {
                    Image(systemName: "waveform")
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                } else if let duration = metadata?.duration {
                    Text(duration.formattedTime)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contextMenu {
            Button {
                isPickingArtwork = true
            } label: {
                Label("Set Cover…", systemImage: "photo.badge.plus")
            }
        }
        .artworkPicker(for: item, isPresented: $isPickingArtwork)
        .task(id: "\(item.url.absoluteString)#\(library.metadataRevision)") {
            metadata = await MetadataLoader.shared.metadata(for: item.url)
        }
    }

    @ViewBuilder private var artwork: some View {
        if let data = metadata?.artworkData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "music.note")
                        .foregroundStyle(.secondary)
                }
        }
    }
}
