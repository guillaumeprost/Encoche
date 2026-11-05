import Foundation
import Observation

struct ClaudeCodeSession: Identifiable, Equatable {
    enum State: Equatable {
        case idle
        case working
        /// En attente de toi (permission à accorder, question posée…).
        case waiting
        case done
        /// Session fermée, ou retrouvée dans l'historique au lancement.
        case inactive
    }

    let id: String
    var cwd: String
    var state: State
    var detail: String?
    var updatedAt: Date
    /// Processus Claude Code (envoyé par les hooks) : sert à retrouver son app.
    var pid: pid_t?
    /// Titre donné à la session par Claude Code (lu dans la transcription).
    var title: String?
    /// Dernière demande envoyée à Claude.
    var prompt: String?
    /// Plan de la tâche en cours (liste de tâches de Claude).
    var plan: [PlanItem] = []
    /// Agents lancés pendant la demande en cours.
    var agents: [SubAgent] = []
    /// Dernière réponse de Claude.
    var lastMessage: String?
    var transcriptPath: String?

    struct PlanItem: Equatable, Identifiable {
        enum Status: Equatable { case pending, inProgress, completed }
        let id: Int
        var content: String
        var status: Status
    }

    struct SubAgent: Equatable, Identifiable {
        let id: String
        var name: String
        var isRunning: Bool
    }

    var planProgress: (done: Int, total: Int) {
        (plan.filter { $0.status == .completed }.count, plan.count)
    }

    var projectName: String { Self.projectName(for: cwd) }

    /// Nom du projet : le dossier de travail de la session.
    static func projectName(for cwd: String) -> String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? "Claude Code" : name
    }

    /// Avancement du plan entre 0 et 1, ou `nil` sans plan.
    var planFraction: Double? {
        let progress = planProgress
        return progress.total > 0 ? Double(progress.done) / Double(progress.total) : nil
    }
}

/// Demande de permission de Claude Code en attente de ta décision dans l'encoche.
@MainActor
final class PendingPermission: Identifiable {
    enum Decision {
        case allow
        /// Autoriser et ajouter la règle suggérée par Claude Code (plus de question la prochaine fois).
        case allowAlways
        case deny
        /// Ne rien décider ici : Claude Code poursuit avec sa demande habituelle dans le terminal.
        case terminal
    }

    let id = UUID()
    let sessionID: String
    let projectName: String
    let toolName: String
    let summary: String
    /// Mises à jour de permissions suggérées par Claude Code (« toujours autoriser »).
    let suggestions: [[String: Any]]
    let reply: HookReply
    var alertID: UUID?

    init(sessionID: String, projectName: String, toolName: String, summary: String,
         suggestions: [[String: Any]], reply: HookReply) {
        self.sessionID = sessionID
        self.projectName = projectName
        self.toolName = toolName
        self.summary = summary
        self.suggestions = suggestions
        self.reply = reply
    }

    var canAllowAlways: Bool { !suggestions.isEmpty }
}

/// État des sessions Claude Code, alimenté par les hooks.
@Observable
@MainActor
final class ClaudeCodeMonitor {
    private static let staleAfter: TimeInterval = 2 * 3600
    /// Sessions gardées dans le sélecteur (les plus récentes).
    static let recentLimit = 5

    private(set) var sessions: [ClaudeCodeSession] = []
    private(set) var permissions: [PendingPermission] = []
    private(set) var hooksInstalled = ClaudeHooksInstaller.isInstalled
    private(set) var hooksError: String?

    private var server: HookServer?
    /// Pour signaler dans l'encoche une session qui t'attend ou qui a fini.
    var alerts: AlertCenter?
    private var cleanupTimer: Timer?

    init() {
        let server = HookServer(
            onEvent: { [weak self] event in self?.handle(event) },
            onPermission: { [weak self] event, reply in self?.handlePermission(event, reply: reply) }
        )
        server.start()
        self.server = server

        // Ajoute les hooks apparus depuis l'installation (ex. demandes de permission).
        if hooksInstalled { try? ClaudeHooksInstaller.install() }

        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.markStaleSessionsInactive() }
        }
        loadRecentSessions()
    }

    /// Retrouve les dernières sessions dans les transcriptions de Claude Code,
    /// pour que le sélecteur ne soit pas vide après un lancement.
    private func loadRecentSessions() {
        Task {
            let found = await ClaudeTranscript.recentSessions(limit: Self.recentLimit + 3)
            for item in found where !sessions.contains(where: { $0.id == item.id }) {
                guard let cwd = item.info.cwd, !isAskSession(cwd) else { continue }
                var session = ClaudeCodeSession(id: item.id, cwd: cwd, state: .inactive, detail: nil, updatedAt: item.date)
                session.title = item.info.title
                session.prompt = item.info.lastPrompt
                session.lastMessage = item.info.lastMessage
                session.transcriptPath = item.path
                sessions.append(session)
            }
            trimSessions()
        }
    }

    /// Session en train de travailler (la plus récente), pour l'activité en direct.
    var workingSession: ClaudeCodeSession? {
        sessions.filter { $0.state == .working }.max { $0.updatedAt < $1.updatedAt }
    }

    var waitingCount: Int { sessions.filter { $0.state == .waiting }.count }
    /// L'encoche repliée signale en continu les sessions qui t'attendent
    /// (les fins de tâche passent par une notification).
    var needsAttention: Bool { waitingCount > 0 }

    /// Plus récentes d'abord, celles qui t'attendent en tête.
    var sortedSessions: [ClaudeCodeSession] {
        sessions.sorted { a, b in
            if (a.state == .waiting) != (b.state == .waiting) { return a.state == .waiting }
            if (a.state == .inactive) != (b.state == .inactive) { return b.state == .inactive }
            return a.updatedAt > b.updatedAt
        }
    }

    func permission(for sessionID: String) -> PendingPermission? {
        permissions.first { $0.sessionID == sessionID }
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

    /// Ramène au premier plan l'app où tourne la session (terminal, éditeur, app Claude…).
    func focus(_ sessionID: String) {
        guard let pid = sessions.first(where: { $0.id == sessionID })?.pid else { return }
        ProcessOwner.activateApp(of: pid)
    }

    /// Envoie un message à la session (tapé dans son terminal, ou collé dans son app).
    func reply(_ text: String, to sessionID: String) async -> ClaudeReply.Outcome {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return .failed("Session introuvable") }
        guard session.state != .inactive, let pid = session.pid else { return .failed("Session fermée") }
        return await ClaudeReply.send(text, toProcess: pid)
    }

    func dismiss(_ session: ClaudeCodeSession) {
        resolvePermissions(of: session.id)
        sessions.removeAll { $0.id == session.id }
    }

    // MARK: - Permissions

    func decide(_ permission: PendingPermission, _ decision: Decision) {
        var output: [String: Any]?
        switch decision {
        case .allow:
            output = ["behavior": "allow"]
        case .allowAlways:
            output = ["behavior": "allow", "updatedPermissions": permission.suggestions]
        case .deny:
            output = ["behavior": "deny", "message": "Refusé depuis Encoche."]
        case .terminal:
            output = nil
        }

        let body = output.flatMap {
            try? JSONSerialization.data(withJSONObject: [
                "hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": $0],
            ])
        }
        permission.reply.send(body)
        remove(permission)

        if decision != .terminal { update(permission.sessionID) { $0.state = .working; $0.detail = permission.toolName } }
    }

    typealias Decision = PendingPermission.Decision

    private func handlePermission(_ event: [String: Any], reply: HookReply) {
        currentPID = event["_claude_pid"] as? pid_t
        defer { currentPID = nil }
        guard let sessionID = event["session_id"] as? String else {
            reply.send(nil)
            return
        }
        let cwd = event["cwd"] as? String ?? ""
        if isAskSession(cwd) {
            reply.send(nil)
            return
        }

        let tool = event["tool_name"] as? String ?? "Outil"
        let input = event["tool_input"] as? [String: Any] ?? [:]
        let permission = PendingPermission(
            sessionID: sessionID,
            projectName: ClaudeCodeSession.projectName(for: cwd),
            toolName: tool,
            summary: ClaudeActivity.summarize(tool: tool, input: input),
            suggestions: event["permission_suggestions"] as? [[String: Any]] ?? [],
            reply: reply
        )
        reply.onClosed = { [weak self, weak permission] in
            guard let self, let permission else { return }
            self.remove(permission)
        }
        permissions.append(permission)

        upsert(sessionID, cwd: cwd) { session in
            session.state = .waiting
            session.detail = "\(tool) · \(permission.summary)"
        }

        var alert = NotchAlert(
            icon: .symbol("hand.raised.fill", .claude),
            source: "Claude Code",
            title: "\(permission.projectName) demande : \(tool)",
            body: permission.summary
        )
        var buttons: [NotchAlert.Button] = [
            .init(label: "Refuser", role: .destructive) { [weak self, weak permission] in
                if let permission { self?.decide(permission, .deny) }
            },
            .init(label: "Terminal", role: .normal) { [weak self, weak permission] in
                if let permission { self?.decide(permission, .terminal) }
            },
        ]
        if permission.canAllowAlways {
            buttons.append(.init(label: "Toujours", role: .normal) { [weak self, weak permission] in
                if let permission { self?.decide(permission, .allowAlways) }
            })
        }
        buttons.append(.init(label: "Autoriser", role: .primary) { [weak self, weak permission] in
            if let permission { self?.decide(permission, .allow) }
        })
        alert.buttons = buttons
        permission.alertID = alert.id
        alerts?.post(alert)
    }

    private func remove(_ permission: PendingPermission) {
        permissions.removeAll { $0 === permission }
        if let alertID = permission.alertID { alerts?.dismiss(alertID: alertID) }
    }

    /// La session a avancé sans nous (réponse dans le terminal, annulation…) :
    /// les demandes en attente n'ont plus lieu d'être.
    private func resolvePermissions(of sessionID: String) {
        for permission in permissions where permission.sessionID == sessionID {
            permission.reply.send(nil)
            remove(permission)
        }
    }

    // MARK: - Événements

    private func isAskSession(_ cwd: String) -> Bool {
        // Les questions rapides de l'encoche passent aussi par Claude Code : on ne les liste pas.
        URL(fileURLWithPath: cwd).standardizedFileURL == ClaudeAsk.workingDirectory.standardizedFileURL
    }

    /// PID de l'événement en cours de traitement (lu par `upsert`).
    @ObservationIgnored private var currentPID: pid_t?

    private func handle(_ event: [String: Any]) {
        currentPID = event["_claude_pid"] as? pid_t
        defer { currentPID = nil }
        guard let id = event["session_id"] as? String,
              let name = event["hook_event_name"] as? String else { return }
        let cwd = event["cwd"] as? String ?? ""
        if isAskSession(cwd) { return }

        // Tout événement qui suit montre que la demande a été tranchée ailleurs.
        if ["PreToolUse", "PostToolUse", "UserPromptSubmit", "Stop", "SessionEnd"].contains(name) {
            resolvePermissions(of: id)
        }

        if name == "SessionEnd" {
            // Gardée dans le sélecteur des dernières sessions.
            update(id) { $0.state = .inactive; $0.detail = nil; $0.pid = nil }
            trimSessions()
            return
        }

        let previousState = sessions.first { $0.id == id }?.state

        let isNew = !sessions.contains { $0.id == id }
        if let path = event["transcript_path"] as? String, !path.isEmpty {
            upsert(id, cwd: cwd) { $0.transcriptPath = path }
            // Session découverte en cours de route (Encoche relancé) : titre et demande sont dans la transcription.
            if isNew && name != "SessionStart" && name != "UserPromptSubmit" { readTranscript(of: id) }
        }

        switch name {
        case "SessionStart":
            upsert(id, cwd: cwd) { $0.state = .idle; $0.detail = nil }
            readTranscript(of: id)
        case "UserPromptSubmit":
            let prompt = (event["prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            upsert(id, cwd: cwd) { session in
                session.state = .working
                session.detail = nil
                session.prompt = prompt?.isEmpty == false ? prompt : session.prompt
                session.agents = []
                session.lastMessage = nil
                // Plan terminé : il appartenait à la demande précédente.
                if session.plan.allSatisfy({ $0.status == .completed }) { session.plan = [] }
            }
            readTranscript(of: id)
        case "PreToolUse":
            let tool = event["tool_name"] as? String ?? ""
            let input = event["tool_input"] as? [String: Any] ?? [:]
            let toolUseID = event["tool_use_id"] as? String
            upsert(id, cwd: cwd) { session in
                session.state = .working
                session.detail = ClaudeActivity.describe(tool: tool, input: input)
                ClaudeActivity.applyPlan(tool: tool, input: input, to: &session.plan)
                if ClaudeActivity.agentTools.contains(tool) {
                    let name = (input["description"] as? String)
                        ?? (input["subagent_type"] as? String) ?? "Agent"
                    session.agents.append(.init(id: toolUseID ?? UUID().uuidString, name: name, isRunning: true))
                }
            }
        case "PostToolUse":
            let tool = event["tool_name"] as? String ?? ""
            let toolUseID = event["tool_use_id"] as? String
            let input = event["tool_input"] as? [String: Any] ?? [:]
            upsert(id, cwd: cwd) { session in
                session.state = .working
                guard ClaudeActivity.agentTools.contains(tool) else { return }
                let name = input["description"] as? String
                let index = session.agents.firstIndex { $0.id == toolUseID }
                    ?? session.agents.firstIndex { $0.isRunning && $0.name == name }
                if let index { session.agents[index].isRunning = false }
            }
        case "Notification":
            let message = event["message"] as? String ?? ""
            let type = event["notification_type"] as? String ?? ""
            // Le rappel « en attente de ta saisie » après une tâche finie n'est pas une alerte.
            if type == "idle_prompt" || message.localizedCaseInsensitiveContains("waiting for your input") {
                return
            }
            // Déjà signalée (demande de permission en cours) : pas de doublon.
            guard previousState != .waiting else { return }
            upsert(id, cwd: cwd) { $0.state = .waiting; $0.detail = message.isEmpty ? nil : message }
            let project = sessions.first { $0.id == id }?.projectName ?? "Claude Code"
            alerts?.post(NotchAlert(
                icon: .symbol("hand.raised.fill", .claude),
                source: "Claude Code",
                title: "\(project) t'attend",
                body: message.isEmpty ? nil : message,
                action: .run { [weak self] in self?.focus(id) }
            ))
        case "Stop":
            upsert(id, cwd: cwd) { session in
                session.state = .done
                session.detail = nil
                for index in session.agents.indices { session.agents[index].isRunning = false }
            }
            announceDone(id, reply: event["last_assistant_message"] as? String)
        default:
            return
        }
    }

    private func upsert(_ id: String, cwd: String, _ change: (inout ClaudeCodeSession) -> Void) {
        var session = sessions.first { $0.id == id }
            ?? ClaudeCodeSession(id: id, cwd: cwd, state: .idle, detail: nil, updatedAt: Date())
        if !cwd.isEmpty { session.cwd = cwd }
        if let pid = currentPID { session.pid = pid }
        change(&session)
        session.updatedAt = Date()
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
            trimSessions()
        }
    }

    private func update(_ id: String, _ change: (inout ClaudeCodeSession) -> Void) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        change(&sessions[index])
        sessions[index].updatedAt = Date()
    }

    /// Relit le titre de la session et la dernière réponse de Claude dans la transcription.
    /// Notification de fin de tâche, avec le début de la réponse de Claude.
    private func announceDone(_ id: String, reply: String?) {
        Task {
            var reply = reply
            if let path = sessions.first(where: { $0.id == id })?.transcriptPath {
                let info = await ClaudeTranscript.read(path: path)
                update(id) { session in
                    if let title = info.title { session.title = title }
                    if let message = info.lastMessage { session.lastMessage = message }
                }
                if reply == nil { reply = info.lastMessage }
            }
            let session = sessions.first { $0.id == id }
            alerts?.post(NotchAlert(
                icon: .symbol("checkmark", .green),
                source: session?.projectName ?? "Claude Code",
                title: "Terminé · \(session?.title ?? session?.projectName ?? "Claude Code")",
                body: reply.map(Self.plainSummary),
                action: .run { [weak self] in self?.focus(id) }
            ))
        }
    }

    /// Réponse de Claude en texte simple sur une ligne (sans titres, listes ni gras Markdown).
    private static func plainSummary(_ text: String) -> String {
        let cleaned = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#>-*• ")) }
            .filter { !$0.isEmpty && !$0.hasPrefix("```") }
            .joined(separator: " ")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
        return cleaned.count > 400 ? String(cleaned.prefix(400)) + "…" : cleaned
    }

    private func readTranscript(of id: String) {
        guard let path = sessions.first(where: { $0.id == id })?.transcriptPath else { return }
        Task {
            let info = await ClaudeTranscript.read(path: path)
            update(id) { session in
                if let title = info.title { session.title = title }
                if session.prompt == nil { session.prompt = info.lastPrompt }
                if let message = info.lastMessage, session.state != .working { session.lastMessage = message }
            }
        }
    }

    /// Une session muette depuis longtemps est sans doute fermée : elle devient inactive.
    private func markStaleSessionsInactive() {
        let limit = Date().addingTimeInterval(-Self.staleAfter)
        for index in sessions.indices where sessions[index].updatedAt < limit && sessions[index].state != .inactive {
            sessions[index].state = .inactive
        }
        trimSessions()
    }

    /// Garde les sessions actives et complète avec les plus récentes, jusqu'à `recentLimit`.
    private func trimSessions() {
        let sorted = sessions.sorted { $0.updatedAt > $1.updatedAt }
        var kept: [ClaudeCodeSession] = []
        for session in sorted where session.state != .inactive || kept.count < Self.recentLimit {
            kept.append(session)
        }
        if kept.count != sessions.count { sessions = kept }
    }
}
