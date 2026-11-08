import AppKit
import Observation
import SwiftUI

/// Suit le morceau en cours : Musique et Spotify en détail, et tout autre lecteur
/// (YouTube dans le navigateur, Deezer, Podcasts…) par le « À l'écoute » de macOS.
///
/// - Les métadonnées arrivent en push via les notifications distribuées des deux apps
///   (pas d'interrogation périodique).
/// - La pochette, la position de lecture et les commandes passent par AppleScript
///   (permission « Automatisation » demandée une seule fois par app).
/// - On ne parle à une app que si elle tourne : `tell application` la lancerait sinon.
@Observable
@MainActor
final class MusicController {
    enum Source: String {
        case music = "com.apple.Music"
        case spotify = "com.spotify.client"

        var isRunning: Bool {
            !NSRunningApplication.runningApplications(withBundleIdentifier: rawValue).isEmpty
        }
    }

    struct Track: Equatable {
        var title: String
        var artist: String
        var album: String
        var duration: Double
    }

    private(set) var source: Source?
    /// App d'un autre lecteur (navigateur pour YouTube…), suivie par le « À l'écoute » de macOS.
    private(set) var externalPlayer: String?

    /// La lecture vient d'une vidéo dans le navigateur (YouTube…), pas d'une app de musique.
    var isPlayingVideo: Bool { PictureInPicture.isSupported(externalPlayer) }
    private(set) var track: Track?
    private(set) var isPlaying = false
    private(set) var artwork: NSImage?
    private(set) var accent: Color = .primary

    @ObservationIgnored private let nowPlaying = NowPlayingAdapter()
    /// Pochette reçue du « À l'écoute », pour ne la redécoder que si elle change.
    @ObservationIgnored private var artworkData: Data?
    /// Dernière pochette du « À l'écoute » pour Musique ou Spotify, avec le titre du morceau :
    /// les titres Apple Music en streaming n'ont pas de pochette par AppleScript.
    @ObservationIgnored private var appArtwork: (title: String, data: Data)?
    private var basePosition: Double = 0
    private var baseDate = Date()

    var showsActivity: Bool { track != nil && isPlaying }

    init() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] note in
            let info = note.userInfo ?? [:]
            MainActor.assumeIsolated { self?.handle(info, from: .music) }
        }
        center.addObserver(forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] note in
            let info = note.userInfo ?? [:]
            MainActor.assumeIsolated { self?.handle(info, from: .spotify) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self else { return }
                if bundleID == self.source?.rawValue || bundleID == self.externalPlayer { self.clear() }
            }
        }

        Task { await loadInitialState() }
        nowPlaying.onUpdate = { [weak self] info in self?.handleExternal(info) }
        nowPlaying.start()
    }

    // MARK: - Position

    func position(at date: Date) -> Double {
        guard let track else { return 0 }
        let elapsed = isPlaying ? date.timeIntervalSince(baseDate) : 0
        return min(max(basePosition + elapsed, 0), track.duration > 0 ? track.duration : .infinity)
    }

    func refreshPosition() {
        // Lecteur externe : la position arrive avec ses mises à jour.
        guard externalPlayer == nil, let source, source.isRunning else { return }
        Task {
            guard let value = await AppleScriptRunner.run(
                "tell application id \"\(source.rawValue)\" to get player position"
            )?.doubleValue, self.source == source else { return }
            setPosition(value)
        }
    }

    private func setPosition(_ value: Double) {
        basePosition = value
        baseDate = Date()
    }

    // MARK: - Commandes

    func playPause() {
        if externalPlayer != nil {
            setPosition(position(at: Date()))
            isPlaying.toggle()
            nowPlaying.send(.togglePlayPause)
            return
        }
        guard let source, source.isRunning else { return }
        refreshPosition()
        isPlaying.toggle()
        baseDate = Date()
        Task { _ = await AppleScriptRunner.run("tell application id \"\(source.rawValue)\" to playpause") }
    }

    func next() {
        if externalPlayer != nil { nowPlaying.send(.next) } else { send("next track") }
    }

    func previous() {
        if externalPlayer != nil { nowPlaying.send(.previous) } else { send("previous track") }
    }

    func seek(to seconds: Double) {
        if externalPlayer != nil {
            setPosition(seconds)
            nowPlaying.seek(to: seconds)
            return
        }
        guard let source, source.isRunning else { return }
        setPosition(seconds)
        Task { _ = await AppleScriptRunner.run("tell application id \"\(source.rawValue)\" to set player position to \(seconds)") }
    }

    func openSourceApp() {
        if let externalPlayer, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: externalPlayer) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
            return
        }
        open(source ?? .music)
    }

    func open(_ source: Source) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.rawValue) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    func isInstalled(_ source: Source) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.rawValue) != nil
    }

    private func send(_ command: String) {
        guard let source, source.isRunning else { return }
        Task { _ = await AppleScriptRunner.run("tell application id \"\(source.rawValue)\" to \(command)") }
    }

    // MARK: - Notifications

    private func handle(_ info: [AnyHashable: Any], from origin: Source) {
        let state = info["Player State"] as? String ?? ""

        if state == "Stopped" {
            if source == origin { clear() }
            return
        }
        // Une app en pause ne vole pas la place de celle qui joue.
        if source != nil, source != origin, state != "Playing", isPlaying { return }

        let durationMs: Double
        switch origin {
        case .music: durationMs = (info["Total Time"] as? NSNumber)?.doubleValue ?? 0
        case .spotify: durationMs = (info["Duration"] as? NSNumber)?.doubleValue ?? 0
        }
        let newTrack = Track(
            title: info["Name"] as? String ?? "",
            artist: info["Artist"] as? String ?? "",
            album: info["Album"] as? String ?? "",
            duration: durationMs / 1000
        )

        let changed = newTrack != track || origin != source
        externalPlayer = nil
        source = origin
        track = newTrack
        isPlaying = state == "Playing"

        if origin == .spotify, let pos = (info["Playback Position"] as? NSNumber)?.doubleValue {
            setPosition(pos)
        } else {
            refreshPosition()
        }
        if changed { loadArtwork() }
    }

    private func loadInitialState() async {
        var paused: (Source, [AnyHashable: Any])?
        for candidate in [Source.spotify, .music] where candidate.isRunning {
            guard let info = await queryState(of: candidate) else { continue }
            // Une notification de l'app est arrivée entre-temps : elle fait foi.
            guard track == nil else { return }
            if info["Player State"] as? String == "Playing" {
                handle(info, from: candidate)
                return
            }
            if paused == nil { paused = (candidate, info) }
        }
        if let (candidate, info) = paused { handle(info, from: candidate) }
    }

    /// Interroge l'app et renvoie un dictionnaire au même format que ses notifications.
    private func queryState(of source: Source) async -> [AnyHashable: Any]? {
        let script = """
        tell application id "\(source.rawValue)"
            if player state is stopped then return {"stopped"}
            set t to current track
            return {player state as string, name of t, artist of t, album of t, duration of t}
        end tell
        """
        guard let result = await AppleScriptRunner.run(script), result.numberOfItems >= 5 else { return nil }
        let rawState = result.atIndex(1)?.stringValue ?? ""
        let duration = result.atIndex(5)?.doubleValue ?? 0
        return [
            "Player State": rawState == "playing" ? "Playing" : "Paused",
            "Name": result.atIndex(2)?.stringValue ?? "",
            "Artist": result.atIndex(3)?.stringValue ?? "",
            "Album": result.atIndex(4)?.stringValue ?? "",
            // Musique donne des secondes, Spotify des millisecondes.
            source == .music ? "Total Time" : "Duration": NSNumber(value: source == .music ? duration * 1000 : duration),
        ]
    }

    // MARK: - Autres lecteurs

    /// Mise à jour du « À l'écoute » de macOS. Musique et Spotify ont leur propre suivi
    /// (plus complet) : seuls les autres lecteurs sont pris ici.
    private func handleExternal(_ info: NowPlayingAdapter.Info?) {
        let appInfo = info.flatMap { Source(rawValue: $0.bundleID) != nil ? $0 : nil }
        if let appInfo { useAppArtwork(from: appInfo) }
        guard let info, appInfo == nil else {
            // Plus rien, ou Musique / Spotify reprend la main.
            if externalPlayer != nil {
                clear()
                Task { await loadInitialState() }
            }
            return
        }
        // Un lecteur en pause ne vole pas la place de Musique ou Spotify qui joue.
        if source != nil, isPlaying, !info.playing { return }

        let newTrack = Track(title: info.title, artist: info.artist, album: info.album, duration: info.duration)
        let changed = newTrack != track || info.bundleID != externalPlayer
        source = nil
        externalPlayer = info.bundleID
        track = newTrack
        isPlaying = info.playing
        setPosition(info.elapsed)
        if let artwork = info.artwork {
            if changed || artworkData != artwork {
                artworkData = artwork
                applyArtwork(NSImage(data: artwork))
            }
        } else if changed {
            artworkData = nil
            applyArtwork(nil)
        }
    }

    private func clear() {
        externalPlayer = nil
        artworkData = nil
        source = nil
        track = nil
        isPlaying = false
        artwork = nil
        accent = .primary
    }

    // MARK: - Pochette

    private func loadArtwork() {
        guard let source, source.isRunning else { return }
        let expected = track

        Task {
            switch source {
            case .music:
                let data = await AppleScriptRunner.run(
                    "tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track"
                )?.data
                guard self.track == expected else { return }
                self.applyArtwork(data.flatMap(NSImage.init(data:)) ?? self.appArtworkImage(for: expected))

            case .spotify:
                guard let urlString = await AppleScriptRunner.run(
                    "tell application id \"com.spotify.client\" to get artwork url of current track"
                )?.stringValue, let url = URL(string: urlString) else {
                    if self.track == expected { self.applyArtwork(nil) }
                    return
                }
                let data = try? await URLSession.shared.data(from: url).0
                guard self.track == expected else { return }
                self.applyArtwork(data.flatMap(NSImage.init(data:)))
            }
        }
    }

    /// Pochette du « À l'écoute » pour Musique / Spotify, quand l'app n'en donne pas elle-même.
    private func useAppArtwork(from info: NowPlayingAdapter.Info) {
        guard let data = info.artwork else { return }
        appArtwork = (info.title, data)
        guard source?.rawValue == info.bundleID, track?.title == info.title, artwork == nil else { return }
        applyArtwork(NSImage(data: data))
    }

    private func appArtworkImage(for track: Track?) -> NSImage? {
        guard let appArtwork, appArtwork.title == track?.title else { return nil }
        return NSImage(data: appArtwork.data)
    }

    private func applyArtwork(_ image: NSImage?) {
        withAnimation(.easeInOut(duration: 0.3)) {
            artwork = image
            accent = image?.vividAverageColor.map(Color.init(nsColor:)) ?? .primary
        }
    }
}
