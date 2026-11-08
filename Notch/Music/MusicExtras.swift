import AppKit
import Observation

/// File d'attente et paroles du morceau en cours, chargées à la demande (onglet Musique).
///
/// - File d'attente : avec Musique, la vraie file est lue dans son panneau de file d'attente
///   (Accessibilité, voir `MusicQueueReader`). Panneau fermé : morceaux suivants de la
///   playlist en cours (bibliothèque, AppleScript).
///   Sinon (Apple Music en streaming, Spotify), on affiche la suite de l'album en cours,
///   trouvée dans le catalogue public d'Apple (iTunes Search : titre, artiste et album envoyés).
/// - Paroles : LRCLIB (lrclib.net), service libre et gratuit, avec paroles synchronisées.
///   Seuls le titre, l'artiste, l'album et la durée du morceau y sont envoyés.
@Observable
@MainActor
final class MusicExtras {
    struct QueueItem: Identifiable, Equatable {
        /// D'où vient le morceau, ce qui décide de ce que fait un clic.
        enum Source: Equatable {
            /// Lu dans la file d'attente de Musique.
            case musicQueue
            /// Morceau de la playlist en cours (bibliothèque), à cette position.
            case playlist(index: Int)
            /// Suite de l'album, d'après le catalogue d'Apple (page du morceau).
            case catalog(URL?)
        }

        let id: Int
        let source: Source
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
    /// La file est la suite de l'album (et non la playlist en cours).
    private(set) var queueIsAlbum = false
    /// Le panneau de file d'attente de Musique est fermé : la vraie file n'est pas lisible.
    private(set) var musicPanelClosed = false
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
            queue = []
            lyrics = []
            queueState = .unavailable
            lyricsState = .unavailable
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
        switch item.source {
        case .musicQueue:
            // Pas de moyen fiable de lancer un morceau de la file : on montre Musique.
            music.open(.music)
        case .catalog(let url):
            guard let url, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") else { return }
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        case .playlist(let index):
            guard music.source == .music else { return }
            Task {
                _ = await AppleScriptRunner.run(
                    "tell application id \"com.apple.Music\" to play track \(index) of current playlist",
                    cached: false
                )
            }
        }
    }

    /// Ligne en cours d'après la position de lecture.
    func currentLineID(at position: Double) -> Int? {
        guard lyricsSynced else { return nil }
        return lyrics.last { ($0.time ?? .infinity) <= position + 0.3 }?.id
    }

    // MARK: - File d'attente

    /// Ouvre le panneau de file d'attente dans Musique, puis relit la file.
    func showMusicQueuePanel() {
        Task {
            await Task.detached { MusicQueueReader.showPanel() }.value
            try? await Task.sleep(for: .milliseconds(600))
            refresh(force: true)
        }
    }

    private func loadQueue(for track: MusicController.Track) {
        queueState = .loading
        musicPanelClosed = false
        guard music.source == .music else {
            loadAlbumQueue(for: track)
            return
        }
        Task {
            // La vraie file, lue dans le panneau de Musique.
            let result = await Task.detached(priority: .userInitiated) { MusicQueueReader.read() }.value
            guard music.track == track else { return }
            switch result {
            case .entries(let entries):
                queue = entries.enumerated().map { offset, entry in
                    QueueItem(id: offset, source: .musicQueue, title: entry.title, artist: entry.artist, duration: 0)
                }
                queueTitle = nil
                queueIsAlbum = false
                queueState = .loaded
            case .panelClosed, .unavailable:
                musicPanelClosed = result.isPanelClosed
                loadPlaylistQueue(for: track)
            }
        }
    }

    private func loadPlaylistQueue(for track: MusicController.Track) {
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
                // Pas de playlist accessible (Apple Music en streaming) : suite de l'album.
                loadAlbumQueue(for: track)
                return
            }
            queueIsAlbum = false
            queueTitle = result.atIndex(1)?.stringValue
            var items: [QueueItem] = []
            if result.numberOfItems >= 2 {
                for position in 2...result.numberOfItems {
                    guard let entry = result.atIndex(position), entry.numberOfItems >= 4,
                        let index = entry.atIndex(1)?.int32Value, index > 0
                    else { continue }
                    items.append(
                        QueueItem(
                            id: position,
                            source: .playlist(index: Int(index)),
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

    private func loadAlbumQueue(for track: MusicController.Track) {
        Task {
            let items = await Self.albumTracks(after: track)
            guard music.track == track else { return }
            queue = items ?? []
            queueTitle = items == nil ? nil : track.album
            queueIsAlbum = true
            queueState = items == nil ? .unavailable : .loaded
        }
    }

    private struct ITunesResults: Decodable {
        struct Item: Decodable {
            let wrapperType: String?
            let collectionId: Int?
            let collectionName: String?
            let artistName: String?
            let trackName: String?
            let trackNumber: Int?
            let discNumber: Int?
            let trackTimeMillis: Double?
            let trackViewUrl: String?
        }
        let results: [Item]
    }

    /// Morceaux de l'album après le morceau en cours, d'après le catalogue public d'Apple.
    private nonisolated static func albumTracks(after track: MusicController.Track) async -> [QueueItem]? {
        guard !track.album.isEmpty else { return nil }
        let country = Locale.current.region?.identifier ?? "FR"
        let wantedAlbum = normalized(track.album)
        let wantedArtist = normalized(track.artist)

        func search(_ term: String, entity: String, attribute: String? = nil) async -> [ITunesResults.Item] {
            var components = URLComponents(string: "https://itunes.apple.com/search")!
            components.queryItems =
                [
                    URLQueryItem(name: "term", value: term), URLQueryItem(name: "entity", value: entity),
                    URLQueryItem(name: "limit", value: "25"), URLQueryItem(name: "country", value: country),
                ] + (attribute.map { [URLQueryItem(name: "attribute", value: $0)] } ?? [])
            guard let data = await request(components.url!) else { return [] }
            return (try? JSONDecoder().decode(ITunesResults.self, from: data))?.results ?? []
        }
        func matches(_ item: ITunesResults.Item) -> Bool {
            normalized(item.collectionName ?? "") == wantedAlbum
                && normalized(item.artistName ?? "").contains(wantedArtist.prefix(12))
        }

        // Le morceau d'abord (donne directement son album), puis l'album par son nom.
        var collection = await search("\(track.artist) \(track.title)", entity: "song").first(where: matches)?.collectionId
        if collection == nil {
            collection = await search(track.album, entity: "album", attribute: "albumTerm").first(where: matches)?.collectionId
        }
        guard let collection else { return nil }

        var lookup = URLComponents(string: "https://itunes.apple.com/lookup")!
        lookup.queryItems = [
            URLQueryItem(name: "id", value: String(collection)), URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "country", value: country),
        ]
        guard let data = await request(lookup.url!),
            let results = try? JSONDecoder().decode(ITunesResults.self, from: data).results
        else { return nil }
        let songs =
            results
            .filter { $0.wrapperType == "track" }
            .sorted { ($0.discNumber ?? 1, $0.trackNumber ?? 0) < ($1.discNumber ?? 1, $1.trackNumber ?? 0) }
        let current = songs.firstIndex { normalized($0.trackName ?? "") == normalized(track.title) }
        let following = current.map { Array(songs[($0 + 1)...]) } ?? songs
        return following.enumerated().map { offset, song in
            QueueItem(
                id: offset,
                source: .catalog(song.trackViewUrl.flatMap(URL.init(string:))),
                title: song.trackName ?? "",
                artist: song.artistName ?? "",
                duration: (song.trackTimeMillis ?? 0) / 1000
            )
        }
    }

    private nonisolated static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
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
            exact.syncedLyrics != nil || exact.plainLyrics != nil
        {
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
            (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return data
    }

    /// Paroles LRC : « [01:23.45] texte ». Sans horodatage, une ligne par ligne.
    nonisolated static func parse(_ text: String, synced: Bool) -> [LyricLine] {
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

extension MusicQueueReader.Result {
    fileprivate var isPanelClosed: Bool { if case .panelClosed = self { true } else { false } }
}
