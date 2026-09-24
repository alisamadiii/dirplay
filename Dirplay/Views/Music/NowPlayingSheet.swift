import SwiftUI

/// Full-screen bottom sheet in the Spotify style: large artwork, title,
/// scrub slider, and transport controls.
struct NowPlayingSheet: View {
    @Environment(PlayerViewModel.self) private var player
    @State private var isPickingArtwork = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            artwork
                .padding(.horizontal, 32)
            Spacer(minLength: 24)
            ZStack {
                VStack(spacing: 6) {
                    Text(player.metadata?.title ?? player.current?.displayName ?? "Nothing Playing")
                        .font(.title2.bold())
                        .lineLimit(1)
                    Text(player.metadata?.artist ?? player.current?.url.deletingLastPathComponent().lastPathComponent ?? " ")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .id(player.current?.url)
                .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.35), value: player.current)
            .padding(.horizontal, 32)
            scrubber
                .padding(.horizontal, 32)
                .padding(.top, 20)
            transportControls
                .padding(.horizontal, 40)
                .padding(.top, 12)
            speedControl
                .padding(.top, 20)
            Spacer(minLength: 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { ambientBackground }
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
        .artworkPicker(for: player.current, isPresented: $isPickingArtwork)
    }

    /// Barely-visible echo of the cover behind the sheet: heavily blurred,
    /// low opacity, strongest at the top and fading out toward the bottom.
    @ViewBuilder private var ambientBackground: some View {
        if let image = player.artworkImage {
            GeometryReader { proxy in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .blur(radius: 60, opaque: true)
                    .opacity(0.35)
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black.opacity(0.5), location: 0.55),
                                .init(color: .clear, location: 0.95)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            }
            .ignoresSafeArea()
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.5), value: player.current)
        }
    }

    // MARK: - Artwork

    /// Always a 1:1 square regardless of cover shape or absence, so the layout
    /// below never shifts. Track changes crossfade instead of snapping.
    @ViewBuilder private var artwork: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack {
                    if let image = player.artworkImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                            .id(player.current?.url)
                    } else {
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.55), Color.accentColor.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.system(size: 72))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .transition(.opacity)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // Only offered once tags are loaded and no cover exists.
                if player.metadata != nil, player.artworkImage == nil {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        isPickingArtwork = true
                    } label: {
                        Label("Add Cover", systemImage: "photo.badge.plus")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                }
            }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
        .animation(.easeInOut(duration: 0.35), value: player.current)
        .animation(.easeInOut(duration: 0.35), value: player.artworkImage == nil)
        .contextMenu {
            if player.current != nil {
                Button {
                    isPickingArtwork = true
                } label: {
                    Label(
                        player.artworkImage == nil ? "Add Cover…" : "Replace Cover…",
                        systemImage: "photo.badge.plus"
                    )
                }
            }
        }
    }

    // MARK: - Scrubber

    private var scrubber: some View {
        VStack(spacing: 4) {
            // Scrub-as-you-drag: every drag movement seeks immediately, so
            // there is no local "scrubbing" state that a cancelled gesture
            // could leave stuck. The player is the single source of truth.
            Slider(
                value: Binding(
                    get: { min(player.currentTime, max(player.duration, 0)) },
                    set: { player.scrub(to: $0) }
                ),
                in: 0...max(player.duration, 1)
            )
            HStack {
                Text(player.currentTime.formattedTime)
                Spacer()
                Text(player.duration.formattedTime)
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Transport

    private var transportControls: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(duration: 0.3)) {
                    player.isShuffling.toggle()
                }
            } label: {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundStyle(player.isShuffling ? Color.accentColor : .secondary)
            }
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title)
            }
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 72))
                    .contentTransition(.symbolEffect(.replace))
            }
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
            }
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(duration: 0.3)) {
                    player.repeatMode = player.repeatMode == .one ? .queue : .one
                }
            } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.title3)
                    .foregroundStyle(player.repeatMode == .one ? Color.accentColor : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    // MARK: - Speed

    private var speedControl: some View {
        Menu {
            ForEach(PlayerViewModel.availableRates, id: \.self) { rate in
                Button {
                    player.rate = rate
                } label: {
                    if rate == player.rate {
                        Label(rateLabel(rate), systemImage: "checkmark")
                    } else {
                        Text(rateLabel(rate))
                    }
                }
            }
        } label: {
            Text(rateLabel(player.rate))
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func rateLabel(_ rate: Float) -> String {
        String(format: rate == rate.rounded() ? "%.0f×" : "%g×", rate)
    }
}
