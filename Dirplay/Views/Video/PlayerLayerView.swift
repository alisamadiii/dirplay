import AVFoundation
import AVKit
import MediaPlayer
import SwiftUI

/// Bare video surface backed by AVPlayerLayer. The system `VideoPlayer`
/// can't hide its controls, so the custom player draws on top of this.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect

    final class LayerHostView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerHostView {
        let view = LayerHostView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: LayerHostView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
        if uiView.playerLayer.videoGravity != gravity {
            // Smooth fit ⇄ fill transition instead of a hard jump.
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.25)
            uiView.playerLayer.videoGravity = gravity
            CATransaction.commit()
        }
    }
}

/// System AirPlay route picker ("connect to TV / Mac"), styled to match the
/// glassy overlay buttons.
struct RoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = .white
        view.prioritizesVideoDevices = true
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// Programmatic system-volume control. There is no public setter, so the
/// standard approach is driving the slider inside a hidden `MPVolumeView` —
/// equivalent to pressing the hardware buttons. No-op in the simulator.
@MainActor
enum SystemVolume {
    private static let volumeView = MPVolumeView(frame: .init(x: -2000, y: -2000, width: 1, height: 1))

    static var current: Float {
        AVAudioSession.sharedInstance().outputVolume
    }

    static func set(_ value: Float) {
        // The slider only responds while the view lives in a window.
        if volumeView.superview == nil,
           let window = UIApplication.shared.connectedScenes
               .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first {
            volumeView.alpha = 0.0001
            window.addSubview(volumeView)
        }
        let clamped = max(0, min(value, 1))
        guard let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.value = clamped
    }
}
