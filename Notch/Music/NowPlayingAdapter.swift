import AppKit

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
        queue.async {
            self.stopLeftovers()
            self.launchStream()
        }
        // Le flux s'arrête avec l'app.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.process?.terminationHandler = nil
            self?.process?.terminate()
        }
    }

    /// Flux laissés par une instance précédente d'Encoche (arrêtée brutalement).
    private func stopLeftovers() {
        guard let framework else { return }
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-f", "\(framework) stream"]
        try? pkill.run()
        pkill.waitUntilExit()
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
            guard let self else { return }
            self.queue.async { self.consume(data) }
        }
        // S'il s'arrête (mise en veille, plantage…), on le relance un peu plus tard.
        process.terminationHandler = { [weak self] _ in
            output.fileHandleForReading.readabilityHandler = nil
            guard let self else { return }
            self.queue.asyncAfter(deadline: .now() + 5) { [weak self] in self?.launchStream() }
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

    static func parse(_ payload: [String: Any], now: Date = Date()) -> Info? {
        guard let title = payload["title"] as? String, !title.isEmpty,
              let bundleID = payload["parentApplicationBundleIdentifier"] as? String
                ?? payload["bundleIdentifier"] as? String else { return nil }
        let playing = payload["playing"] as? Bool ?? false
        var elapsed = payload["elapsedTime"] as? Double ?? 0
        // La position est donnée à un instant : on l'avance jusqu'à maintenant.
        if playing, let stamp = payload["timestamp"] as? String, let date = Self.date(from: stamp) {
            elapsed += now.timeIntervalSince(date)
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

    /// Date ISO 8601, avec ou sans fractions de seconde.
    private static func date(from text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }

    /// Commande ponctuelle (lecture, morceau suivant, position).
    private func run(_ arguments: [String]) {
        guard let script, let framework else { return }
        Task { _ = await ProcessRunner.run(Self.perl, [script, framework] + arguments) }
    }
}
