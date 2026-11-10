import SwiftUI

// MARK: - Repliée : pochette à gauche de l'encoche, égaliseur à droite

struct CollapsedMusicView: View {
    @Environment(MusicController.self) private var music
    let slotWidth: CGFloat

    var body: some View {
        CollapsedActivityLayout(slotWidth: slotWidth) {
            Artwork(image: music.artwork, cornerRadius: 5)
                .frame(width: 20, height: 20)
                // Petit rebond quand le morceau change.
                .keyframeAnimator(initialValue: 1.0, trigger: music.track?.title) { view, scale in
                    view.scaleEffect(scale)
                } keyframes: { _ in
                    SpringKeyframe(1.25, duration: 0.18, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
                }
        } trailing: {
            AudioBars(isPlaying: music.isPlaying, color: music.accent)
        }
    }
}

/// Nouveau morceau : titre et artiste sous l'encoche repliée. La pochette reste
/// au-dessus, dans l'activité, qui rebondit au même moment.
struct TrackHUDView: View {
    @Environment(MusicController.self) private var music
    @State private var shown = false

    var body: some View {
        if let track = music.track {
            HStack(spacing: 6) {
                reveal(
                    Text(track.title).font(.system(size: 11, weight: .semibold)),
                    delay: 0.08
                )
                .layoutPriority(1)
                if !track.artist.isEmpty {
                    reveal(
                        Text(track.artist).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)),
                        delay: 0.16
                    )
                }
            }
            .lineLimit(1)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .onAppear { shown = true }
        }
    }

    /// Le texte descend de sous l'encoche en sortant du flou.
    private func reveal(_ text: some View, delay: Double) -> some View {
        text
            .blur(radius: shown ? 0 : 6)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : -8)
            .animation(.smooth(duration: 0.45).delay(delay), value: shown)
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
                .glassButton(in: Circle(), isShown: hovering)
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
                    .gesture(
                        DragGesture(minimumDistance: 0)
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
        return Clock.text(s)
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
                // Rempli et recadré : une vignette vidéo (16:9) ne déborde pas du carré.
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
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

// MARK: - Onglet Musique

/// Onglet Musique : le lecteur à gauche, les paroles ou la file d'attente à droite.
struct MusicTab: View {
    @Environment(MusicController.self) private var music
    @Environment(MusicExtras.self) private var extras
    @AppStorage("musicSidePanel") private var showsQueue = false

    var body: some View {
        if music.track == nil {
            EmptyMusicView()
                .padding(.horizontal, 40)
        } else if music.externalPlayer != nil {
            // Vidéo ou autre lecteur (YouTube…) : pas de paroles ni de file, le lecteur prend la place.
            VideoPlayerView()
                .foregroundStyle(.primary)
        } else {
            HStack(spacing: 20) {
                MusicTabPlayer()
                    .frame(width: 270)
                Rectangle()
                    .fill(.primary.opacity(0.12))
                    .frame(width: 1)
                    .padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: $showsQueue) {
                        Text("Paroles").tag(false)
                        Text("À suivre").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                    .frame(maxWidth: .infinity)

                    if showsQueue {
                        QueueView()
                    } else {
                        LyricsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .foregroundStyle(.primary)
            .onAppear { extras.refresh() }
            .onChange(of: music.track) { extras.refresh() }
        }
    }
}

/// Lecteur de l'onglet Musique, en colonne.
private struct MusicTabPlayer: View {
    @Environment(MusicController.self) private var music

    var body: some View {
        if let track = music.track {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    Artwork(image: music.artwork, cornerRadius: 14)
                        .frame(width: 96, height: 96)
                        .shadow(color: music.accent.opacity(0.4), radius: 14, y: 5)
                        .onTapGesture { music.openSourceApp() }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(2)
                        Text(track.artist)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(0.65))
                            .lineLimit(1)
                        if !track.album.isEmpty {
                            Text(track.album)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.primary.opacity(0.45))
                                .lineLimit(1)
                        }
                        AudioBars(isPlaying: music.isPlaying, color: music.accent)
                            .frame(width: 22, height: 14)
                            .padding(.top, 4)
                    }
                }
                if track.duration > 0 {
                    ProgressBar(duration: track.duration)
                }
                Controls()
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// Paroles, synchronisées quand c'est possible : la ligne en cours est mise en avant.
private struct LyricsView: View {
    @Environment(MusicController.self) private var music
    @Environment(MusicExtras.self) private var extras

    var body: some View {
        switch extras.lyricsState {
        case .idle, .loading:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable:
            placeholder("Pas de paroles pour ce morceau", symbol: "quote.bubble")
        case .loaded:
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let current = extras.currentLineID(at: music.position(at: context.date))
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(extras.lyrics) { line in
                                Text(line.text)
                                    .font(.system(size: 14.5, weight: .semibold))
                                    .foregroundStyle(.primary.opacity(opacity(of: line, current: current)))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(line.id)
                                    .onTapGesture { if let time = line.time { music.seek(to: time) } }
                            }
                        }
                        .padding(.vertical, 40)
                    }
                    .scrollIndicators(.never)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0), .init(color: .black, location: 0.15),
                                .init(color: .black, location: 0.85), .init(color: .clear, location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .onChange(of: current) {
                        guard let current else { return }
                        withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(current, anchor: .center) }
                    }
                    .onAppear { if let current { proxy.scrollTo(current, anchor: .center) } }
                }
                .animation(.easeOut(duration: 0.25), value: current)
            }
        }
    }

    private func opacity(of line: MusicExtras.LyricLine, current: Int?) -> Double {
        guard extras.lyricsSynced else { return 0.8 }
        guard let current else { return 0.35 }
        return line.id == current ? 1 : 0.3
    }
}

/// Morceaux suivants de la playlist ou de l'album en cours (Musique uniquement).
private struct QueueView: View {
    @Environment(MusicController.self) private var music
    @Environment(MusicExtras.self) private var extras

    var body: some View {
        switch extras.queueState {
        case .idle, .loading:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable:
            VStack(spacing: 8) {
                placeholder(
                    music.source == .spotify
                        ? "Album introuvable dans le catalogue d'Apple"
                        : extras.musicPanelClosed
                            ? "Ouvre la file d'attente dans Musique pour la voir ici"
                            : "Pas de playlist en cours, et album introuvable dans le catalogue d'Apple",
                    symbol: "list.bullet"
                )
                if extras.musicPanelClosed {
                    Button("Afficher la file dans Musique") { extras.showMusicQueuePanel() }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            if extras.queue.isEmpty {
                placeholder("Plus rien après ce morceau", symbol: "list.bullet")
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let title = extras.queueTitle {
                            Text(extras.queueIsAlbum ? "Suite de l'album · \(title)" : title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.primary.opacity(0.45))
                                .padding(.bottom, 2)
                        }
                        ForEach(extras.queue) { item in
                            QueueRow(item: item) { extras.play(item) }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }
}

private struct QueueRow: View {
    let item: MusicExtras.QueueItem
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: hovering ? "play.fill" : "music.note")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.5))
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Text(item.artist).font(.system(size: 11)).foregroundStyle(.primary.opacity(0.5)).lineLimit(1)
                }
                Spacer(minLength: 4)
                if item.duration > 0 {
                    Text(Clock.text(Int(item.duration)))
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.primary.opacity(0.4))
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(hovering ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Lire maintenant")
    }
}

private func placeholder(_ text: String, symbol: String) -> some View {
    VStack(spacing: 6) {
        Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(.primary.opacity(0.4))
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.primary.opacity(0.5))
            .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}

/// Mini-lecteur en haut à droite de l'encoche ouverte : pochette, lecture/pause, suivant.
struct MiniMusicControls: View {
    @Environment(MusicController.self) private var music
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 2) {
            Button {
                settings.tab = .music
            } label: {
                Artwork(image: music.artwork, cornerRadius: 4)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help(music.track.map { "\($0.title) · \($0.artist)" } ?? "Musique")
            .padding(.trailing, 2)
            MiniButton(symbol: music.isPlaying ? "pause.fill" : "play.fill") { music.playPause() }
            MiniButton(symbol: "forward.fill") { music.next() }
        }
    }
}

private struct MiniButton: View {
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22, height: 22)
                .glassButton(in: Circle(), isShown: hovering)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Vidéo (YouTube…) et autres lecteurs

/// Lecteur d'une vidéo ou d'un autre lecteur : vignette au format vidéo, commandes et image dans l'image.
private struct VideoPlayerView: View {
    @Environment(MusicController.self) private var music
    @State private var pipOutcome: PictureInPicture.Outcome?
    @State private var pipRunning = false

    var body: some View {
        if let track = music.track {
            HStack(spacing: 18) {
                Artwork(image: music.artwork, cornerRadius: 14)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(height: 124)
                    .shadow(color: music.accent.opacity(0.4), radius: 14, y: 5)
                    .onTapGesture { music.openSourceApp() }

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            Text(track.artist)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary.opacity(0.65))
                                .lineLimit(1)
                            if let app = appName {
                                Text("· \(app)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.primary.opacity(0.4))
                                    .lineLimit(1)
                            }
                        }
                    }
                    if track.duration > 0 {
                        ProgressBar(duration: track.duration)
                    }
                    HStack {
                        Controls()
                        if music.isPlayingVideo {
                            pipButton
                        }
                    }
                    if case .needsJavaScriptPermission(let browser) = pipOutcome {
                        Text(
                            "Pour l'image dans l'image, active « Autoriser le JavaScript des Apple Events » dans \(browser) › Réglages › Développeur."
                        )
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: track) { pipOutcome = nil }
        }
    }

    private var appName: String? {
        guard let bundleID = music.externalPlayer,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private var pipButton: some View {
        Button {
            guard let player = music.externalPlayer, !pipRunning else { return }
            pipRunning = true
            Task {
                pipOutcome = await PictureInPicture.toggle(in: player)
                pipRunning = false
            }
        } label: {
            Image(systemName: pipOutcome == .done ? "pip.exit" : "pip.enter")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Image dans l'image")
        .opacity(pipRunning ? 0.5 : 1)
    }
}
