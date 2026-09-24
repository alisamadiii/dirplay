import SwiftUI

/// Persistent bar shown above the tab bar while something is loaded.
/// Tapping it opens the full Now Playing sheet.
struct MiniPlayerBar: View {
    @Environment(PlayerViewModel.self) private var player

    var body: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                Text(player.metadata?.title ?? player.current?.displayName ?? "")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if let artist = player.metadata?.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title3)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            player.isPresentingNowPlaying = true
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    @ViewBuilder private var artwork: some View {
        if let image = player.artworkImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
        }
    }
}

private struct MiniPlayerInset: ViewModifier {
    @Environment(PlayerViewModel.self) private var player

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if player.current != nil {
                MiniPlayerBar()
            }
        }
    }
}

extension View {
    /// Shows the mini player above the tab bar inside this tab.
    func miniPlayerInset() -> some View {
        modifier(MiniPlayerInset())
    }
}
