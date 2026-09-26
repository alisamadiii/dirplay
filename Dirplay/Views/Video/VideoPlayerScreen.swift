import AVKit
import SwiftUI

/// Custom full-screen video player: glassy overlay controls, double-tap to
/// skip, scrub preview, swipe-down to dismiss, landscape support.
struct VideoPlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(PlayerViewModel.self) private var musicPlayer
    let item: MediaItem

    @State private var viewModel = VideoPlayerViewModel()
    @State private var controlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?
    // Double-tap skip feedback (accumulates on repeated taps).
    @State private var skipFeedback: SkipFeedback?
    @State private var skipFeedbackTask: Task<Void, Never>?
    // Scrubbing state lives in the view only for preview-card layout;
    // playback truth stays in the view model.
    @State private var isScrubbingForPreview = false
    @State private var scrubFraction: Double = 0
    // Manual double-tap detection (see handleTap).
    @State private var lastTapAt: Date = .distantPast
    @State private var pendingToggleTask: Task<Void, Never>?
    // Pinch-to-zoom: fit (letterboxed) ⇄ fill (cropped edge-to-edge).
    @State private var isFillingScreen = false
    @State private var pinchScale: CGFloat = 1
    // Landscape vertical swipes: left half = brightness, right = volume.
    private enum SwipeAdjust { case brightness, volume }
    @State private var swipeAdjust: SwipeAdjust?
    @State private var swipeBaseline: Float = 0
    @State private var swipeValue: Float = 0
    @State private var swipeHUDTask: Task<Void, Never>?
    @State private var showSwipeHUD = false

    private struct SkipFeedback: Equatable {
        var forward: Bool
        var seconds: Int
        var id = 0 // changes retrigger the animation
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                PlayerLayerView(
                    player: viewModel.player,
                    gravity: isFillingScreen ? .resizeAspectFill : .resizeAspect
                )
                .scaleEffect(pinchScale)
                .ignoresSafeArea()

                // Tap layer BELOW the controls (doubles as the dim scrim).
                // Buttons sit above it, so a tap on X/AirPlay/speed reaches
                // the button directly and never races this gesture. Manual
                // double-tap detection keeps every tap instant (a system
                // double-tap recognizer would delay all touches by the
                // disambiguation window).
                Color.black.opacity(controlsVisible ? 0.35 : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        handleTap(at: location, in: proxy.size)
                    }
                    // Press and hold anywhere: temporary 2× until release.
                    .onLongPressGesture(minimumDuration: 0.4) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        viewModel.beginHoldSpeed()
                    } onPressingChanged: { pressing in
                        if !pressing { viewModel.endHoldSpeed() }
                    }
                    .simultaneousGesture(brightnessVolumeSwipe(in: proxy.size))

                doubleTapFeedback(in: proxy.size)

                if showSwipeHUD, let adjust = swipeAdjust {
                    swipeHUD(for: adjust, in: proxy.size)
                }

                if viewModel.isHoldSpeeding {
                    HStack(spacing: 6) {
                        Text("2×")
                        Image(systemName: "forward.fill")
                    }
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.4), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 6)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.15), value: viewModel.isHoldSpeeding)
                }

                // Controls show and hide instantly — no fade, per user
                // preference.
                if controlsVisible {
                    controlsOverlay
                }
            }
            .simultaneousGesture(pinchToZoom)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden(!controlsVisible)
        .onAppear {
            musicPlayer.pause()
            AppDelegate.orientationLock = .allButUpsideDown
            viewModel.load(item.url)
            scheduleControlsHide()
            #if DEBUG
            runVideoTestIfRequested()
            #endif
        }
        .onDisappear {
            viewModel.tearDown()
            AppDelegate.orientationLock = .portrait
            AppDelegate.snapToPortrait()
        }
        .onChange(of: viewModel.isPlaying) { _, playing in
            if playing {
                scheduleControlsHide()
            } else {
                hideControlsTask?.cancel()
                controlsVisible = true
            }
        }
    }

    // MARK: - Controls overlay

    /// Minimal flat chrome over a dim scrim: X + AirPlay top-left, speed +
    /// volume top-right, skip/play glyphs center, thin bar with elapsed and
    /// remaining time at the bottom.
    private var controlsOverlay: some View {
        ZStack {
            // Transport row lives on its own layer so it is geometrically
            // centered regardless of the top/bottom bar heights (the VStack
            // spacers pushed it off-center in landscape).
            // Hit areas are much larger than the glyphs so play/pause and the
            // skips land without precision aiming.
            HStack(spacing: 16) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.skipBackward()
                    scheduleControlsHide()
                } label: {
                    Image(systemName: "gobackward.\(Int(viewModel.skipInterval))")
                        .font(.system(size: 26, weight: .medium))
                        .frame(width: 80, height: 96)
                        .contentShape(Rectangle())
                }
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    viewModel.togglePlayPause()
                    scheduleControlsHide()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 104, height: 104)
                        .contentShape(Rectangle())
                }
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.skipForward()
                    scheduleControlsHide()
                } label: {
                    Image(systemName: "goforward.\(Int(viewModel.skipInterval))")
                        .font(.system(size: 26, weight: .medium))
                        .frame(width: 80, height: 96)
                        .contentShape(Rectangle())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            VStack {
                // All three chrome controls share the same 52 pt footprint
                // and visual weight (AirPlay's glyph is fixed by the system
                // at ~22 pt, so the others match it).
                HStack(spacing: 20) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 52, height: 52)
                            .contentShape(Circle())
                    }
                    .glassChrome(in: Circle())
                    RoutePickerView()
                        // The system draws its glyph oversized and slightly
                        // high; scale and nudge it to sit like the X icon.
                        .scaleEffect(0.8)
                        .offset(y: 2)
                        .frame(width: 52, height: 52)
                        .glassChrome(in: Circle())
                    Spacer()
                    speedMenu
                }
                .padding(.horizontal, 16)
                // Landscape has no status bar clearance, so the top row
                // needs extra breathing room there; portrait sits as before.
                .padding(.top, verticalSizeClass == .compact ? 24 : 4)

                Spacer()

                bottomBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            VideoScrubber(
                viewModel: viewModel,
                isScrubbing: $isScrubbingForPreview,
                fraction: $scrubFraction,
                onInteraction: scheduleControlsHide
            )
            HStack {
                Text(viewModel.currentTime.formattedTime)
                Spacer()
                Text("-" + max(viewModel.duration - viewModel.currentTime, 0).formattedTime)
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.8))
        }
    }

    private var speedMenu: some View {
        Menu {
            ForEach(PlayerViewModel.availableRates, id: \.self) { rate in
                Button {
                    viewModel.rate = rate
                    scheduleControlsHide()
                } label: {
                    if rate == viewModel.rate {
                        Label(rateLabel(rate), systemImage: "checkmark")
                    } else {
                        Text(rateLabel(rate))
                    }
                }
            }
        } label: {
            Text(rateLabel(viewModel.rate))
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .padding(.horizontal, 16)
                .frame(minWidth: 52)
                .frame(height: 52)
                .contentShape(Capsule())
        }
        .glassChrome(in: Capsule())
    }

    private func rateLabel(_ rate: Float) -> String {
        String(format: rate == rate.rounded() ? "%.0f×" : "%g×", rate)
    }

    // MARK: - Tap handling

    /// Double-tapping shows ONLY the skip arrows — never the controls. The
    /// single-tap controls toggle therefore waits out the double-tap window;
    /// a second tap inside it cancels the pending toggle and skips instead.
    /// Buttons themselves are separate views above this layer and always
    /// react instantly.
    ///
    /// Taps in the chrome bands (top buttons, bottom scrubber) are special:
    /// they never skip, and they never hide controls out from under the
    /// finger — a near-miss on the X keeps the controls up for a second try.
    private func handleTap(at location: CGPoint, in size: CGSize) {
        let inChromeBand = location.y < 140 || location.y > size.height - 160
        if inChromeBand {
            pendingToggleTask?.cancel()
            if !controlsVisible { controlsVisible = true }
            scheduleControlsHide()
            lastTapAt = .distantPast
            return
        }
        let now = Date()
        if now.timeIntervalSince(lastTapAt) < 0.3 {
            pendingToggleTask?.cancel()
            handleDoubleTap(at: location, in: size)
        } else {
            pendingToggleTask?.cancel()
            pendingToggleTask = Task {
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled else { return }
                toggleControls()
            }
        }
        lastTapAt = now
    }

    private func handleDoubleTap(at location: CGPoint, in size: CGSize) {
        let forward = location.x > size.width / 2
        let interval = Int(viewModel.skipInterval)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if forward {
            viewModel.skipForward()
        } else {
            viewModel.skipBackward()
        }
        // Same side twice in a row: accumulate the shown seconds.
        var next = SkipFeedback(forward: forward, seconds: interval)
        if let current = skipFeedback, current.forward == forward {
            next.seconds = current.seconds + interval
            next.id = current.id + 1
        }
        withAnimation(.spring(duration: 0.25)) {
            skipFeedback = next
        }
        skipFeedbackTask?.cancel()
        skipFeedbackTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                skipFeedback = nil
            }
        }
    }

    /// YouTube-style: doubled arrows pointing the way of the jump with the
    /// seconds count beside them.
    @ViewBuilder private func doubleTapFeedback(in size: CGSize) -> some View {
        if let feedback = skipFeedback {
            HStack(spacing: 8) {
                if feedback.forward {
                    Image(systemName: "forward.fill")
                    Text("\(feedback.seconds)s")
                } else {
                    Text("\(feedback.seconds)s")
                    Image(systemName: "backward.fill")
                }
            }
            .font(.title3.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.4), in: Capsule())
            .position(
                x: feedback.forward ? size.width * 0.78 : size.width * 0.22,
                y: size.height / 2
            )
            .id(feedback.id)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }

    // MARK: - Landscape brightness/volume swipes

    /// Landscape only: vertical drag on the left half changes screen
    /// brightness, on the right half changes system volume. The chrome bands
    /// (top buttons, bottom scrubber) are excluded.
    private func brightnessVolumeSwipe(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                guard verticalSizeClass == .compact else { return }
                if swipeAdjust == nil {
                    // Vertical intent only, started outside the chrome bands.
                    guard abs(value.translation.height) > abs(value.translation.width),
                          value.startLocation.y > 140,
                          value.startLocation.y < size.height - 160
                    else { return }
                    let side: SwipeAdjust = value.startLocation.x < size.width / 2 ? .brightness : .volume
                    swipeAdjust = side
                    swipeBaseline = side == .brightness ? Float(UIScreen.main.brightness) : SystemVolume.current
                    swipeHUDTask?.cancel()
                    showSwipeHUD = true
                }
                guard let adjust = swipeAdjust else { return }
                let delta = Float(-value.translation.height / 250)
                let newValue = max(0, min(swipeBaseline + delta, 1))
                swipeValue = newValue
                switch adjust {
                case .brightness: UIScreen.main.brightness = CGFloat(newValue)
                case .volume: SystemVolume.set(newValue)
                }
            }
            .onEnded { _ in
                guard swipeAdjust != nil else { return }
                swipeHUDTask?.cancel()
                swipeHUDTask = Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    guard !Task.isCancelled else { return }
                    showSwipeHUD = false
                    swipeAdjust = nil
                }
            }
    }

    private func swipeHUD(for adjust: SwipeAdjust, in size: CGSize) -> some View {
        VStack(spacing: 8) {
            Image(systemName: adjust == .brightness ? "sun.max.fill" : "speaker.wave.2.fill")
                .font(.subheadline.weight(.semibold))
            Capsule()
                .fill(.white.opacity(0.3))
                .frame(width: 5, height: 120)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(.white)
                        .frame(width: 5, height: 120 * CGFloat(swipeValue))
                }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .background(.black.opacity(0.4), in: Capsule())
        .position(
            x: adjust == .brightness ? size.width * 0.12 : size.width * 0.88,
            y: size.height / 2
        )
        .allowsHitTesting(false)
    }

    // MARK: - Pinch to zoom

    /// YouTube's gesture: pinch out snaps the video to fill the screen
    /// (cropping the letterbox bars), pinch in returns it to fit. The video
    /// follows the fingers with a rubber-band scale while pinching.
    private var pinchToZoom: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                pinchScale = min(max(value, 0.85), 1.25)
            }
            .onEnded { value in
                let wasFilling = isFillingScreen
                if value > 1.05 {
                    isFillingScreen = true
                } else if value < 0.95 {
                    isFillingScreen = false
                }
                if isFillingScreen != wasFilling {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                withAnimation(.easeOut(duration: 0.25)) {
                    pinchScale = 1
                }
            }
    }

    // MARK: - Controls visibility

    private func toggleControls() {
        controlsVisible.toggle()
        if controlsVisible {
            scheduleControlsHide()
        }
    }

    private func scheduleControlsHide() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            if viewModel.isPlaying, !isScrubbingForPreview {
                controlsVisible = false
            }
        }
    }

    #if DEBUG
    /// Headless-simulator smoke test driven by the `-videotest` launch arg:
    /// exercises skip, scrub + preview generation, rate, and play/pause.
    private func runVideoTestIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-videotest") else { return }
        Task {
            try? await Task.sleep(for: .seconds(3))
            let base = viewModel.currentTime
            print("VIDEOTEST t=3s: currentTime=\(base) duration=\(viewModel.duration) playing=\(viewModel.isPlaying)")
            // Rapid triple-tap: targets must accumulate from the intended
            // position, not from the lagging playhead.
            let skipStart = Date()
            viewModel.skipForward()
            viewModel.skipForward()
            viewModel.skipForward()
            let shownImmediately = viewModel.currentTime
            try? await Task.sleep(for: .seconds(1))
            let settleDelay = Date().timeIntervalSince(skipStart)
            print("VIDEOTEST rapid 3x skipForward(\(Int(viewModel.skipInterval))s): shown=\(shownImmediately) (expected \(base + 3 * viewModel.skipInterval)), after \(String(format: "%.2f", settleDelay))s playhead=\(viewModel.player.currentTime().seconds)")
            viewModel.skipBackward()
            try? await Task.sleep(for: .seconds(1))
            print("VIDEOTEST after skipBackward: currentTime=\(viewModel.currentTime)")
            // Simulate a slider drag with preview requests.
            for step in 1...8 {
                viewModel.scrub(to: viewModel.duration * Double(step) / 16)
                try? await Task.sleep(for: .milliseconds(60))
            }
            try? await Task.sleep(for: .milliseconds(400))
            let hadPreview = viewModel.previewImage != nil
            viewModel.endScrub(at: viewModel.duration / 2)
            print("VIDEOTEST after scrub to mid: currentTime=\(viewModel.currentTime) preview=\(hadPreview)")
            try? await Task.sleep(for: .seconds(2))
            print("VIDEOTEST +2s ticking: currentTime=\(viewModel.currentTime)")
            viewModel.beginHoldSpeed()
            print("VIDEOTEST holdSpeed on: player.rate=\(viewModel.player.rate)")
            viewModel.endHoldSpeed()
            print("VIDEOTEST holdSpeed off: player.rate=\(viewModel.player.rate)")
            viewModel.rate = 2.0
            try? await Task.sleep(for: .seconds(1))
            print("VIDEOTEST rate=2: player.rate=\(viewModel.player.rate)")
            viewModel.togglePlayPause()
            print("VIDEOTEST paused: playing=\(viewModel.isPlaying)")
            isFillingScreen = true
            print("VIDEOTEST fill=on")
            try? await Task.sleep(for: .seconds(2))
            isFillingScreen = false
            print("VIDEOTEST fill=off")
            print("VIDEOTEST done")
        }
    }
    #endif
}

// MARK: - Scrubber

/// Custom track + thumb with a floating frame-preview card while dragging.
/// Continuous drags scrub the player directly; release does an exact seek to
/// the previewed position.
private extension View {
    /// Native Liquid Glass on new systems, material fallback on iOS 17–25.
    @ViewBuilder func glassChrome(in shape: some Shape) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}

private struct VideoScrubber: View {
    let viewModel: VideoPlayerViewModel
    @Binding var isScrubbing: Bool
    @Binding var fraction: Double
    var onInteraction: () -> Void

    // Recent drag positions. On release, the finger lifting off shifts the
    // touch by a point or two — enough to jump many seconds on a long video.
    // The seek uses the newest sample from before the lift instead.
    @State private var dragSamples: [(at: Date, fraction: Double)] = []

    // Thin at rest; swells under the finger while scrubbing.
    private var trackHeight: CGFloat { isScrubbing ? 7 : 3 }
    private let thumbSize: CGFloat = 14
    private let previewSize = CGSize(width: 132, height: 74)

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let progress = displayedFraction
            let thumbX = progress * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.3))
                    .frame(height: trackHeight)
                Capsule()
                    .fill(.white)
                    .frame(width: max(thumbX, trackHeight), height: trackHeight)
                // Plain thin bar at rest; the thumb only materialises under
                // the finger while scrubbing.
                Circle()
                    .fill(.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .scaleEffect(isScrubbing ? 1.3 : 0.01)
                    .opacity(isScrubbing ? 1 : 0)
                    .offset(x: thumbX - thumbSize / 2)
                    .animation(.spring(duration: 0.2), value: isScrubbing)
            }
            .frame(maxHeight: .infinity)
            .animation(.spring(duration: 0.2), value: isScrubbing)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isScrubbing = true
                        fraction = min(max(value.location.x / width, 0), 1)
                        // Stale entries (a cancelled earlier drag) age out.
                        dragSamples.removeAll { $0.at < Date().addingTimeInterval(-0.5) }
                        dragSamples.append((at: Date(), fraction: fraction))
                        if dragSamples.count > 12 { dragSamples.removeFirst() }
                        viewModel.scrub(to: fraction * viewModel.duration)
                        onInteraction()
                    }
                    .onEnded { _ in
                        let cutoff = Date().addingTimeInterval(-0.08)
                        let settled = dragSamples.last(where: { $0.at <= cutoff })?.fraction ?? fraction
                        fraction = settled
                        dragSamples.removeAll()
                        viewModel.endScrub(at: settled * viewModel.duration)
                        isScrubbing = false
                        onInteraction()
                    }
            )
            .overlay(alignment: .topLeading) {
                if isScrubbing {
                    previewCard
                        .frame(width: previewSize.width)
                        .offset(
                            x: min(max(thumbX - previewSize.width / 2, -20), width - previewSize.width + 20),
                            y: -(previewSize.height + 34)
                        )
                        .transition(.opacity)
                }
            }
        }
        .frame(height: 24)
    }

    /// While dragging, the thumb tracks the finger; otherwise it tracks
    /// playback.
    private var displayedFraction: Double {
        guard viewModel.duration > 0 else { return 0 }
        return isScrubbing ? fraction : min(viewModel.currentTime / viewModel.duration, 1)
    }

    private var previewCard: some View {
        VStack(spacing: 4) {
            ZStack {
                Color.black
                if let image = viewModel.previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: previewSize.width, height: previewSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.white.opacity(0.4), lineWidth: 1)
            }
            Text((fraction * viewModel.duration).formattedTime)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.black.opacity(0.6), in: Capsule())
        }
        .allowsHitTesting(false)
    }
}
