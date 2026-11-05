import Foundation
import Observation

/// File d'attente et paroles du morceau en cours, chargées à la demande (onglet Musique).
///
/// - File d'attente : seulement avec Musique, qui expose la playlist en cours par AppleScript
///   (Spotify ne donne pas accès à sa file). Ce sont les morceaux qui suivent dans la playlist
///   ou l'album en cours ; la file « À suivre » ajoutée à la main n'est pas accessible.
/// - Paroles : LRCLIB (lrclib.net), service libre et gratuit, avec paroles synchronisées.
///   Seuls le titre, l'artiste, l'album et la durée du morceau y sont envoyés.
@Observable
@MainActor
final class MusicExtras {
    struct QueueItem: Identifiable, Equatable {
        let id: Int
        /// Position dans la playlist (pour la lancer).
        let index: Int
        let title: String
        let artist: String
        let duration: Double
    }

    struct LyricLine: Identifiable, Equatable {
        let id: Int
        let time: Double?
        let text: String
    }

    enum LoadState: Equatable { case idle, loading, loaded, unavailable }

    private(set) var queue: [QueueItem] = []
    private(set) var queueTitle: String?
    private(set) var queueState: LoadState = .idle
    private(set) var lyrics: [LyricLine] = []
    private(set) var lyricsSynced = false
    private(set) var lyricsState: LoadState = .idle

    @ObservationIgnored private let music: MusicController
    @ObservationIgnored private var loadedTrack: MusicController.Track?
    @ObservationIgnored private var lyricsCache: [String: ([LyricLine], Bool)] = [:]

    init(music: MusicController) {
        self.music = music
    }

    /// Recharge si le morceau a changé (appelé à l'affichage de l'onglet et à chaque changement).
    func refresh(force: Bool = false) {
        guard let track = music.track else {
            queue = []; lyrics = []; queueState = .unavailable; lyricsState = .unavailable
            loadedTrack = nil
            return
        }
        guard force || track != loadedTrack else { return }
        loadedTrack = track
        loadQueue(for: track)
        loadLyrics(for: track)
    }

    /// Lance un morceau de la file.
    func play(_ item: QueueItem) {
        guard music.source == .music else { return }
        Task {
            _ = await AppleScriptRunner.run(
                "tell application id \"com.apple.Music\" to play track \(item.index) of current playlist",
                cached: false
            )
        }
    }

    /// Ligne en cours d'après la position de lecture.
    func currentLineID(at position: Double) -> Int? {
        guard lyricsSynced else { return nil }
        return lyrics.last { ($0.time ?? .infinity) <= position + 0.3 }?.id
    }

    // MARK: - File d'attente

    private func loadQueue(for track: MusicController.Track) {
        guard music.source == .music else {
            queue = []
            queueTitle = nil
            queueState = .unavailable
            return
        }
        queueState = .loading
        let script = """
        tell application id "com.apple.Music"
            set pl to current playlist
            set idx to index of current track
            set n to count of tracks of pl
            set out to {name of pl}
            repeat with i from idx + 1 to idx + 15
                if i > n then exit repeat
                set t to track i of pl
                set end of out to {i, name of t, artist of t, duration of t}
            end repeat
            return out
        end tell
        """
        Task {
            let result = await AppleScriptRunner.run(script, cached: false)
            guard music.track == track else { return }
            guard let result, result.numberOfItems >= 1 else {
                queue = []
                queueTitle = nil
                queueState = .unavailable
                return
            }
            queueTitle = result.atIndex(1)?.stringValue
            var items: [QueueItem] = []
            if result.numberOfItems >= 2 {
                for position in 2...result.numberOfItems {
                    guard let entry = result.atIndex(position), entry.numberOfItems >= 4 else { continue }
                    items.append(QueueItem(
                        id: position,
                        index: Int(entry.atIndex(1)?.int32Value ?? 0),
                        title: entry.atIndex(2)?.stringValue ?? "",
                        artist: entry.atIndex(3)?.stringValue ?? "",
                        duration: entry.atIndex(4)?.doubleValue ?? 0
                    ))
                }
            }
            queue = items
            queueState = .loaded
        }
    }

    // MARK: - Paroles

    private func loadLyrics(for track: MusicController.Track) {
        let key = "\(track.artist)|\(track.title)"
        if let cached = lyricsCache[key] {
            lyrics = cached.0
            lyricsSynced = cached.1
            lyricsState = cached.0.isEmpty ? .unavailable : .loaded
            return
        }
        lyrics = []
        lyricsState = .loading
        Task {
            let found = await Self.fetchLyrics(for: track)
            guard music.track == track else { return }
            let lines = found.map { Self.parse($0.synced ?? $0.plain ?? "", synced: $0.synced != nil) } ?? []
            let synced = found?.synced != nil
            lyricsCache[key] = (lines, synced)
            lyrics = lines
            lyricsSynced = synced
            lyricsState = lines.isEmpty ? .unavailable : .loaded
        }
    }

    private struct LRCLibResult: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    private nonisolated static func fetchLyrics(for track: MusicController.Track) async -> (synced: String?, plain: String?)? {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        var query = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
        ]
        if !track.album.isEmpty { query.append(URLQueryItem(name: "album_name", value: track.album)) }
        if track.duration > 0 { query.append(URLQueryItem(name: "duration", value: String(Int(track.duration.rounded())))) }
        components.queryItems = query

        if let exact = await request(components.url!).flatMap({ try? JSONDecoder().decode(LRCLibResult.self, from: $0) }),
           exact.syncedLyrics != nil || exact.plainLyrics != nil {
            return (exact.syncedLyrics, exact.plainLyrics)
        }
        // Pas de correspondance exacte (album ou durée différents) : recherche plus large.
        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
        ]
        guard let data = await request(search.url!),
              let results = try? JSONDecoder().decode([LRCLibResult].self, from: data),
              let best = results.first(where: { $0.syncedLyrics != nil }) ?? results.first
        else { return nil }
        return (best.syncedLyrics, best.plainLyrics)
    }

    private nonisolated static func request(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        // LRCLIB demande d'identifier le client.
        request.setValue("Encoche (https://github.com/guillaumeprost/Encoche)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    /// Paroles LRC : « [01:23.45] texte ». Sans horodatage, une ligne par ligne.
    private nonisolated static func parse(_ text: String, synced: Bool) -> [LyricLine] {
        var lines: [LyricLine] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw)
            var time: Double?
            if synced, line.hasPrefix("["), let close = line.firstIndex(of: "]") {
                let stamp = line[line.index(after: line.startIndex)..<close]
                let parts = stamp.split(separator: ":")
                if parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) {
                    time = minutes * 60 + seconds
                }
                line = String(line[line.index(after: close)...])
            }
            let content = line.trimmingCharacters(in: .whitespaces)
            // Lignes vides gardées en synchronisé (pauses instrumentales), sinon ignorées en tête.
            if content.isEmpty && (lines.isEmpty || !synced) { continue }
            lines.append(LyricLine(id: lines.count, time: time, text: content.isEmpty ? "♪" : content))
        }
        return lines
    }
}
