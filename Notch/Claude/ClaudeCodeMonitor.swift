import Foundation
import Observation

struct ClaudeCodeSession: Identifiable, Equatable {
    enum State: Equatable {
        case idle
        case working
        /// En attente de toi (permission à accorder, question posée…).
        case waiting
        case done
    }

    let id: String
    var cwd: String
    var state: State
    var detail: String?
    var updatedAt: Date

    var projectName: String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? "Claude Code" : name
    }
}

/// État des sessions Claude Code, alimenté par les hooks.
@Observable
@MainActor
final class ClaudeCodeMonitor {
    /// Combien de temps une fin de tâche reste signalée dans l'encoche repliée.
    private static let finishedFlash: TimeInterval = 6
    private static let staleAfter: TimeInterval = 2 * 3600

    private(set) var sessions: [ClaudeCodeSession] = []
    private(set) var hooksInstalled = ClaudeHooksInstaller.isInstalled
    private(set) var hooksError: String?
    private(set) var flashUntil: Date?

    private var server: HookServer?
    private var cleanupTimer: Timer?

    init() {
        let server = HookServer { [weak self] event in self?.handle(event) }
        server.start()
        self.server = server

        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.removeStale() }
        }
    }

    var waitingCount: Int { sessions.filter { $0.state == .waiting }.count }
    var isFlashingFinished: Bool { flashUntil.map { $0 > Date() } ?? false }

    /// L'encoche repliée doit-elle signaler quelque chose ?
    var needsAttention: Bool { waitingCount > 0 || isFlashingFinished }

    /// Plus récentes d'abord, celles qui t'attendent en tête.
    var sortedSessions: [ClaudeCodeSession] {
        sessions.sorted { a, b in
            if (a.state == .waiting) != (b.state == .waiting) { return a.state == .waiting }
            return a.updatedAt > b.updatedAt
        }
    }

    // MARK: - Hooks

    func installHooks() {
        do {
            try ClaudeHooksInstaller.install()
            hooksError = nil
        } catch {
            hooksError = error.localizedDescription
        }
        hooksInstalled = ClaudeHooksInstaller.isInstalled
    }

    func uninstallHooks() {
        do {
            try ClaudeHooksInstaller.uninstall()
            hooksError = nil
        } catch {
            hooksError = error.localizedDescription
        }
        hooksInstalled = ClaudeHooksInstaller.isInstalled
    }

    func dismiss(_ session: ClaudeCodeSession) {
        sessions.removeAll { $0.id == session.id }
    }

    // MARK: - Événements

    private func handle(_ event: [String: Any]) {
        guard let id = event["session_id"] as? String,
              let name = event["hook_event_name"] as? String else { return }
        let cwd = event["cwd"] as? String ?? ""
        // Les questions rapides de l'encoche passent aussi par Claude Code : on ne les liste pas.
        if URL(fileURLWithPath: cwd).standardizedFileURL == ClaudeAsk.workingDirectory.standardizedFileURL { return }

        if name == "SessionEnd" {
            sessions.removeAll { $0.id == id }
            return
        }

        var session = sessions.first { $0.id == id }
            ?? ClaudeCodeSession(id: id, cwd: cwd, state: .idle, detail: nil, updatedAt: Date())
        if !cwd.isEmpty { session.cwd = cwd }

        switch name {
        case "SessionStart":
            session.state = .idle
            session.detail = nil
        case "UserPromptSubmit":
            session.state = .working
            session.detail = nil
        case "PreToolUse":
            session.state = .working
            session.detail = event["tool_name"] as? String
        case "Notification":
            let message = event["message"] as? String ?? ""
            let type = event["notification_type"] as? String ?? ""
            // Le rappel « en attente de ta saisie » après une tâche finie n'est pas une alerte.
            if type == "idle_prompt" || message.localizedCaseInsensitiveContains("waiting for your input") {
                return
            }
            session.state = .waiting
            session.detail = message.isEmpty ? nil : message
        case "Stop":
            session.state = .done
            session.detail = nil
            flashUntil = Date().addingTimeInterval(Self.finishedFlash)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.finishedFlash + 0.1))
                // Force la réévaluation de `needsAttention`.
                if let self, !self.isFlashingFinished { self.flashUntil = nil }
            }
        default:
            return
        }

        session.updatedAt = Date()
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
    }

    private func removeStale() {
        let limit = Date().addingTimeInterval(-Self.staleAfter)
        sessions.removeAll { $0.updatedAt < limit }
    }
}
