import AppKit
import Observation
import SwiftUI

/// Suit le morceau en cours dans Musique et Spotify.
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
    private(set) var track: Track?
    private(set) var isPlaying = false
    private(set) var artwork: NSImage?
    private(set) var accent: Color = .primary

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
                if let self, bundleID == self.source?.rawValue { self.clear() }
            }
        }

        loadInitialState()
    }

    // MARK: - Position

    func position(at date: Date) -> Double {
        guard let track else { return 0 }
        let elapsed = isPlaying ? date.timeIntervalSince(baseDate) : 0
        return min(max(basePosition + elapsed, 0), track.duration > 0 ? track.duration : .infinity)
    }

    func refreshPosition() {
        guard let source, source.isRunning,
              let value = AppleScriptRunner.run("tell application id \"\(source.rawValue)\" to get player position")?.doubleValue
        else { return }
        setPosition(value)
    }

    private func setPosition(_ value: Double) {
        basePosition = value
        baseDate = Date()
    }

    // MARK: - Commandes

    func playPause() {
        guard let source, source.isRunning else { return }
        refreshPosition()
        isPlaying.toggle()
        baseDate = Date()
        AppleScriptRunner.run("tell application id \"\(source.rawValue)\" to playpause")
    }

    func next() { send("next track") }
    func previous() { send("previous track") }

    func seek(to seconds: Double) {
        guard let source, source.isRunning else { return }
        setPosition(seconds)
        AppleScriptRunner.run("tell application id \"\(source.rawValue)\" to set player position to \(seconds)")
    }

    func openSourceApp() {
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
        AppleScriptRunner.run("tell application id \"\(source.rawValue)\" to \(command)")
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

    private func loadInitialState() {
        var paused: (Source, [AnyHashable: Any])?
        for candidate in [Source.spotify, .music] where candidate.isRunning {
            guard let info = queryState(of: candidate) else { continue }
            if info["Player State"] as? String == "Playing" {
                handle(info, from: candidate)
                return
            }
            if paused == nil { paused = (candidate, info) }
        }
        if let (candidate, info) = paused { handle(info, from: candidate) }
    }

    /// Interroge l'app et renvoie un dictionnaire au même format que ses notifications.
    private func queryState(of source: Source) -> [AnyHashable: Any]? {
        let script = """
        tell application id "\(source.rawValue)"
            if player state is stopped then return {"stopped"}
            set t to current track
            return {player state as string, name of t, artist of t, album of t, duration of t}
        end tell
        """
        guard let result = AppleScriptRunner.run(script), result.numberOfItems >= 5 else { return nil }
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

    private func clear() {
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

        switch source {
        case .music:
            let data = AppleScriptRunner.run(
                "tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track"
            )?.data
            applyArtwork(data.flatMap(NSImage.init(data:)))

        case .spotify:
            guard let urlString = AppleScriptRunner.run(
                "tell application id \"com.spotify.client\" to get artwork url of current track"
            )?.stringValue, let url = URL(string: urlString) else {
                applyArtwork(nil)
                return
            }
            Task {
                let data = try? await URLSession.shared.data(from: url).0
                guard self.track == expected else { return }
                self.applyArtwork(data.flatMap(NSImage.init(data:)))
            }
        }
    }

    private func applyArtwork(_ image: NSImage?) {
        withAnimation(.easeInOut(duration: 0.3)) {
            artwork = image
            accent = image?.vividAverageColor.map(Color.init(nsColor:)) ?? .primary
        }
    }
}
