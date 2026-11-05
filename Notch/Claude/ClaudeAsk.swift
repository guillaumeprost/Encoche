import Foundation
import Observation

/// Question rapide à Claude depuis l'encoche, via la CLI Claude Code en mode `--print`.
///
/// Passe par l'abonnement Claude déjà connecté dans la CLI : pas de clé API, pas de
/// facturation à part (ça compte dans les limites d'usage de l'abonnement).
/// Chaque question est un échange indépendant, sans outils ni session conservée.
@Observable
@MainActor
final class ClaudeAsk {
    /// Dossier de travail des questions. Les hooks venant de ce dossier sont ignorés
    /// par `ClaudeCodeMonitor`, pour ne pas lister ces questions comme des sessions.
    static let workingDirectory: URL = {
        let url = URL.appSupport.appendingPathComponent("ask", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private static let systemPrompt = """
    Tu réponds dans une petite fenêtre logée dans l'encoche d'un Mac. Sois direct et concis : \
    quelques phrases ou une courte liste suffisent dans la plupart des cas. Pas de titres ni de \
    tableaux ; le gras, l'italique et le `code` en ligne s'affichent correctement. Réponds dans \
    la langue de la question.
    """

    private static let cliCandidates = [
        "~/.local/bin/claude",
        "~/.claude/local/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
    ]

    struct Exchange: Identifiable {
        let id = UUID()
        let question: String
        let answer: String
    }

    var question = ""
    /// Destinataire des champs Claude (accueil, onglet Claude). `nil` : la session par défaut.
    enum Target: Equatable {
        case session(String)
        /// Nouvelle conversation dans l'app Claude.
        case newConversation
        /// Question rapide, répondue dans l'encoche.
        case quickQuestion
    }

    /// Destinataire du champ de l'onglet Claude (`nil` : la session choisie ou la plus urgente).
    var target: Target?
    /// Destinataire du champ de l'accueil (`nil` : une nouvelle conversation dans Claude Chat).
    var homeTarget: Target?
    /// Échanges précédents de la conversation en cours (le dernier est `askedQuestion` / `answer`).
    private(set) var history: [Exchange] = []
    private(set) var askedQuestion = ""
    private(set) var answer = ""
    private(set) var isStreaming = false
    private(set) var errorMessage: String?
    /// La dernière erreur vient d'une connexion expirée ou absente.
    private(set) var needsLogin = false

    let cliURL: URL? = ClaudeAsk.cliCandidates
        .map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
        .first { FileManager.default.isExecutableFile(atPath: $0.path) }

    /// Session Claude Code de la conversation : reprise à chaque question pour garder le fil.
    private var sessionID: String?
    private var process: Process?
    private var task: Task<Void, Never>?
    /// Pour annoncer la réponse (l'encoche a pu se refermer pendant qu'elle arrivait).
    @ObservationIgnored var alerts: AlertCenter?
    @ObservationIgnored var openAnswer: () -> Void = {}

    // MARK: - Questions

    func send() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let cliURL else { return }

        cancel()
        // L'échange précédent (terminé) rejoint l'historique de la conversation.
        if !askedQuestion.isEmpty, !answer.isEmpty {
            history.append(Exchange(question: askedQuestion, answer: answer))
        }
        askedQuestion = text
        question = ""
        answer = ""
        errorMessage = nil
        needsLogin = false
        isStreaming = true

        task = Task { [weak self] in
            await self?.run(text, cli: cliURL)
            // Une question annulée a été remplacée : ne pas toucher à l'état de la suivante.
            guard !Task.isCancelled, let self else { return }
            self.isStreaming = false
            self.announceAnswer()
        }
    }

    /// Notification avec le début de la réponse ; un clic montre l'onglet Claude.
    private func announceAnswer() {
        guard errorMessage == nil, !answer.isEmpty else { return }
        let plain = answer.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "**", with: "")
        alerts?.post(NotchAlert(
            icon: .symbol("sparkle", .claude),
            source: "Claude",
            title: "Claude a répondu · \(askedQuestion)",
            body: plain.count > 300 ? String(plain.prefix(300)) + "…" : plain,
            action: .run { [weak self] in self?.openAnswer() }
        ))
    }

    func cancel() {
        task?.cancel()
        task = nil
        if let process, process.isRunning { process.terminate() }
        process = nil
        isStreaming = false
    }

    /// Nouvelle conversation : on oublie le fil.
    func reset() {
        cancel()
        sessionID = nil
        history = []
        askedQuestion = ""
        answer = ""
        errorMessage = nil
        needsLogin = false
    }

    private func run(_ text: String, cli: URL) async {
        let process = Process()
        process.executableURL = cli
        process.currentDirectoryURL = Self.workingDirectory
        process.arguments = [
            "-p", text,
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--tools", "",
            "--system-prompt", Self.systemPrompt,
        ] + (sessionID.map { ["--resume", $0] } ?? [])
        // Une app lancée depuis le Finder n'a qu'un PATH minimal.
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = [cli.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin",
                               "/usr/bin", "/bin", environment["PATH"] ?? ""].joined(separator: ":")
        process.environment = environment

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            errorMessage = "Impossible de lancer Claude Code : \(error.localizedDescription)"
            return
        }
        self.process = process

        do {
            for try await line in stdout.fileHandleForReading.bytes.lines {
                guard !Task.isCancelled else { break }
                guard let data = line.data(using: .utf8),
                      let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }
                handle(event)
            }
        } catch {
            if !Task.isCancelled { errorMessage = "Lecture de la réponse interrompue." }
        }
    }

    private func handle(_ event: [String: Any]) {
        if let id = event["session_id"] as? String { sessionID = id }
        switch event["type"] as? String {
        case "stream_event":
            guard let inner = event["event"] as? [String: Any],
                  inner["type"] as? String == "content_block_delta",
                  let delta = inner["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let text = delta["text"] as? String else { return }
            answer += text

        case "result":
            let result = event["result"] as? String ?? ""
            if event["is_error"] as? Bool == true {
                answer = ""
                // Conversation impossible à reprendre : la prochaine question repart de zéro.
                sessionID = nil
                let status = event["api_error_status"] as? Int
                needsLogin = status == 401 || result.localizedCaseInsensitiveContains("authenticat")
                errorMessage = needsLogin
                    ? "La connexion de Claude Code a expiré."
                    : (result.isEmpty ? "Claude Code a renvoyé une erreur." : result)
            } else if answer.isEmpty {
                // Pas de streaming partiel reçu : on prend la réponse finale.
                answer = result
            }

        default:
            break
        }
    }
}
