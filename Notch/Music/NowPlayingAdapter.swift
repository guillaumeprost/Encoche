import Foundation

/// Lit le « À l'écoute » de macOS (YouTube dans le navigateur, Deezer, Podcasts…) et le pilote.
///
/// macOS réserve cet accès à ses propres apps : on passe par MediaRemoteAdapter
/// (`Vendor/MediaRemoteAdapter`), un framework chargé par `/usr/bin/perl`, qui y a droit.
/// Le flux (`stream`) envoie une ligne JSON à chaque changement de morceau ou de lecture.
final class NowPlayingAdapter: @unchecked Sendable {
    struct Info: Sendable {
        /// App qui joue (navigateur pour une vidéo YouTube).
        let bundleID: String
        let title: String
        let artist: String
        let album: String
        let duration: Double
        let playing: Bool
        /// Position de lecture estimée maintenant.
        let elapsed: Double
        let artwork: Data?
    }

    /// Commandes de MediaRemote (`MRCommand`).
    enum Command: Int {
        case togglePlayPause = 2
        case next = 4
        case previous = 5
    }

    /// Appelé sur le fil principal, avec `nil` quand plus rien ne joue.
    var onUpdate: (@MainActor (Info?) -> Void)?

    private let queue = DispatchQueue(label: "com.guillaumeprost.notch.nowplaying")
    private var process: Process?
    private var buffer = Data()

    private static let perl = "/usr/bin/perl"
    private var script: String? { Bundle.main.path(forResource: "mediaremote-adapter", ofType: "pl") }
    private var framework: String? {
        Bundle.main.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework").path
    }

    func start() {
        queue.async { self.launchStream() }
    }

    func send(_ command: Command) {
        run(["send", String(command.rawValue)])
    }

    func seek(to seconds: Double) {
        run(["seek", String(Int(seconds * 1_000_000))])
    }

    // MARK: - Flux

    private func launchStream() {
        guard let script, let framework else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.perl)
        process.arguments = [script, framework, "stream", "--no-diff", "--debounce=150"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.queue.async { self?.consume(data) }
        }
        // S'il s'arrête (mise en veille, plantage…), on le relance un peu plus tard.
        process.terminationHandler = { [weak self] _ in
            output.fileHandleForReading.readabilityHandler = nil
            self?.queue.asyncAfter(deadline: .now() + 5) { self?.launchStream() }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            NSLog("[Encoche] Now playing adapter failed to start: \(error)")
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  json["type"] as? String == "data" else { continue }
            let info = Self.parse(json["payload"] as? [String: Any] ?? [:])
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.onUpdate?(info) }
            }
        }
    }

    private static func parse(_ payload: [String: Any]) -> Info? {
        guard let title = payload["title"] as? String, !title.isEmpty,
              let bundleID = payload["parentApplicationBundleIdentifier"] as? String
                ?? payload["bundleIdentifier"] as? String else { return nil }
        let playing = payload["playing"] as? Bool ?? false
        var elapsed = payload["elapsedTime"] as? Double ?? 0
        // La position est donnée à un instant : on l'avance jusqu'à maintenant.
        if playing, let stamp = payload["timestamp"] as? String,
           let date = ISO8601DateFormatter().date(from: stamp) {
            elapsed += Date().timeIntervalSince(date)
        }
        return Info(
            bundleID: bundleID,
            title: title,
            artist: payload["artist"] as? String ?? "",
            album: payload["album"] as? String ?? "",
            duration: payload["duration"] as? Double ?? 0,
            playing: playing,
            elapsed: elapsed,
            artwork: (payload["artworkData"] as? String).flatMap { Data(base64Encoded: $0) }
        )
    }

    /// Commande ponctuelle (lecture, morceau suivant, position).
    private func run(_ arguments: [String]) {
        guard let script, let framework else { return }
        Task { _ = await ProcessRunner.run(Self.perl, [script, framework] + arguments) }
    }
}
