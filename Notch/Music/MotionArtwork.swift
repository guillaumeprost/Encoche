import AVFoundation
import AppKit
import SwiftUI

/// Pochette du lecteur : animée quand l'album en a une sur Apple Music, comme sur iOS.
/// La vidéo n'apparaît qu'une fois sa première image prête, par-dessus la pochette fixe.
struct AnimatedArtwork: View {
    @Environment(MusicController.self) private var music
    @Environment(MusicExtras.self) private var extras
    let cornerRadius: CGFloat
    @State private var readyVideo: URL?

    var body: some View {
        Artwork(image: music.artwork, cornerRadius: cornerRadius)
            .overlay {
                if let url = extras.motionArtwork {
                    LoopingVideo(url: url) { readyVideo = url }
                        .opacity(readyVideo == url ? 1 : 0)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .allowsHitTesting(false)
                        .id(url)
                }
            }
            .animation(.easeInOut(duration: 0.6), value: readyVideo)
            .task(id: music.track) { extras.loadMotionArtwork() }
    }
}

/// Fond de l'onglet Musique : la pochette (animée si l'album en a une) occupe la partie
/// gauche sur toute la hauteur, puis se fond dans sa version floutée et répétée en miroir,
/// qui prolonge ses couleurs vers la droite.
struct MusicBackdrop: View {
    @Environment(MusicController.self) private var music
    /// Largeur de la colonne du lecteur, jusqu'au séparateur : la pochette la remplit.
    let playerWidth: CGFloat

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            ZStack(alignment: .leading) {
                Color.black
                if let image = music.artwork {
                    // La pochette répétée en miroir vers la droite, puis floutée : au bord de
                    // l'image nette, le flou prolonge exactement les mêmes couleurs.
                    HStack(spacing: 0) {
                        ForEach(0..<Int((geo.size.width / max(playerWidth, 1)).rounded(.up)), id: \.self) { index in
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: playerWidth, height: height)
                                .clipped()
                                .scaleEffect(x: index.isMultiple(of: 2) ? 1 : -1)
                        }
                    }
                    .frame(width: geo.size.width, height: height, alignment: .leading)
                    .clipped()
                    .blur(radius: 40, opaque: true)
                    .saturation(1.3)
                    .overlay(Color.black.opacity(0.4))
                }
                AnimatedArtwork(cornerRadius: 0)
                    .frame(width: playerWidth, height: height)
                    .mask(
                        LinearGradient(
                            stops: [.init(color: .black, location: 0.75), .init(color: .clear, location: 1)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                // Lisibilité du titre et des commandes, en bas à gauche.
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: music.artwork.map(ObjectIdentifier.init))
    }
}

/// Vidéo HLS muette, en boucle, recadrée pour remplir son cadre.
struct LoopingVideo: NSViewRepresentable {
    let url: URL
    let onReady: @MainActor @Sendable () -> Void

    func makeNSView(context: Context) -> PlayerView {
        PlayerView(url: url, onReady: onReady)
    }

    func updateNSView(_ view: PlayerView, context: Context) {}

    static func dismantleNSView(_ view: PlayerView, coordinator: ()) {
        view.stop()
    }

    final class PlayerView: NSView {
        private let player = AVQueuePlayer()
        private var looper: AVPlayerLooper?
        private var readiness: NSKeyValueObservation?

        init(url: URL, onReady: @escaping @MainActor @Sendable () -> Void) {
            super.init(frame: .zero)
            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.videoGravity = .resizeAspectFill
            layer = playerLayer
            wantsLayer = true
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            readiness = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { layer, _ in
                guard layer.isReadyForDisplay else { return }
                Task { @MainActor in onReady() }
            }
            player.play()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        func stop() {
            readiness = nil
            looper?.disableLooping()
            player.pause()
            player.removeAllItems()
        }
    }
}
