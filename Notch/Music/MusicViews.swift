import SwiftUI

// MARK: - Repliée : pochette à gauche de l'encoche, égaliseur à droite

struct CollapsedMusicView: View {
    @Environment(MusicController.self) private var music
    let slotWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Artwork(image: music.artwork, cornerRadius: 5)
                .frame(width: 20, height: 20)
                .frame(width: slotWidth)
            Spacer(minLength: 0)
            AudioBars(isPlaying: music.isPlaying, color: music.accent)
                .frame(width: slotWidth)
        }
    }
}

// MARK: - Ouverte : lecteur complet

struct ExpandedMusicView: View {
    @Environment(MusicController.self) private var music

    var body: some View {
        if let track = music.track {
            HStack(spacing: 16) {
                Artwork(image: music.artwork, cornerRadius: 14)
                    .frame(width: 84, height: 84)
                    .shadow(color: music.accent.opacity(0.35), radius: 12, y: 4)
                    .onTapGesture { music.openSourceApp() }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.system(size: 12))
                                .foregroundStyle(.primary.opacity(0.6))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        AudioBars(isPlaying: music.isPlaying, color: music.accent)
                            .frame(width: 22, height: 14)
                    }

                    if track.duration > 0 {
                        ProgressBar(duration: track.duration)
                    }

                    Controls()
                }
            }
            .foregroundStyle(.primary)
        } else {
            EmptyMusicView()
        }
    }
}

private struct Controls: View {
    @Environment(MusicController.self) private var music

    var body: some View {
        HStack(spacing: 28) {
            ControlButton(symbol: "backward.fill", size: 16) { music.previous() }
            ControlButton(symbol: music.isPlaying ? "pause.fill" : "play.fill", size: 22) { music.playPause() }
                .contentTransition(.symbolEffect(.replace))
            ControlButton(symbol: "forward.fill", size: 16) { music.next() }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 34, height: 30)
                .background(Circle().fill(.primary.opacity(hovering ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

private struct ProgressBar: View {
    @Environment(MusicController.self) private var music
    let duration: Double
    @State private var dragFraction: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let current = dragFraction.map { $0 * duration } ?? music.position(at: context.date)
            HStack(spacing: 8) {
                Text(format(current))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.2))
                        Capsule().fill(music.accent)
                            .frame(width: geo.size.width * min(current / duration, 1))
                    }
                    .frame(height: dragFraction == nil ? 4 : 6)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { dragFraction = min(max($0.location.x / geo.size.width, 0), 1) }
                        .onEnded { _ in
                            if let f = dragFraction { music.seek(to: f * duration) }
                            dragFraction = nil
                        })
                }
                .frame(height: 12)
                Text("-" + format(max(duration - current, 0)))
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.primary.opacity(0.55))
            .animation(.easeOut(duration: 0.15), value: dragFraction == nil)
        }
    }

    private func format(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct EmptyMusicView: View {
    @Environment(MusicController.self) private var music

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "music.note")
                .font(.system(size: 22))
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 12).fill(.primary.opacity(0.08)))
            VStack(alignment: .leading, spacing: 8) {
                Text("Rien en lecture")
                    .font(.system(size: 14, weight: .semibold))
                HStack(spacing: 8) {
                    if music.isInstalled(.music) {
                        Button("Musique") { music.open(.music) }
                    }
                    if music.isInstalled(.spotify) {
                        Button("Spotify") { music.open(.spotify) }
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
            Spacer()
        }
        .foregroundStyle(.primary)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Briques

struct Artwork: View {
    let image: NSImage?
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(.primary.opacity(0.1))
                Image(systemName: "music.note").foregroundStyle(.primary.opacity(0.5))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Petit égaliseur animé, figé quand la lecture est en pause.
struct AudioBars: View {
    let isPlaying: Bool
    let color: Color

    private let speeds: [Double] = [5.1, 7.3, 4.2, 6.4]
    private let phases: [Double] = [0, 1.3, 2.1, 0.7]

    var body: some View {
        // ~7 images/s lissées par une animation : même rendu qu'à 60 images/s, pour bien moins
        // de calcul (l'égaliseur tourne en continu pendant la lecture).
        // En pause : barres immobiles, aucune mise à jour.
        TimelineView(.periodic(from: .now, by: isPlaying ? 0.15 : 3600)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: isPlaying ? 4 + 10 * abs(sin(t * speeds[i] / 2 + phases[i])) : 3)
                        .animation(.easeInOut(duration: 0.15), value: t)
                }
            }
            .frame(height: 14)
        }
    }
}
