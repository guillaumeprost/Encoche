import AppKit
import Observation

/// État des sessions Claude Code, alimenté par les hooks.
@Observable
@MainActor
final class ClaudeCodeMonitor {
    private static let staleAfter: TimeInterval = 2 * 3600
    /// Sessions gardées dans le sélecteur (les plus récentes).
    static let recentLimit = 5

    private(set) var sessions: [ClaudeCodeSession] = []
    private(set) var permissions: [PendingPermission] = []
    /// Dernier appel d'outil annoncé par session (PreToolUse), pour relier la demande qui suit.
    @ObservationIgnored private var lastToolUse: [String: (tool: String, id: String)] = [:]
    @ObservationIgnored private var answerCheck: Timer?
    /// Alerte qui attend ta réponse (« … t'attend », « … te demande »), retirée dès que la session reprend.
    @ObservationIgnored private var waitingAlerts: [String: UUID] = [:]
    private(set) var hooksInstalled = ClaudeHooksInstaller.isInstalled
    private(set) var hooksError: String?

    private var server: HookServer?
    /// Pour signaler dans l'encoche une session qui t'attend ou qui a fini.
    var alerts: AlertCenter?
    private var cleanupTimer: Timer?

    /// L'app de la session (terminal, app Claude) est au premier plan : pas besoin de notification.
    @ObservationIgnored var isSessionAppInFront: @MainActor (pid_t?) -> Bool = ClaudeCodeMonitor.isAppInFront

    /// `listens: false` (tests) : ni serveur de hooks, ni minuteurs, ni lecture des transcriptions.
    init(listens: Bool = true) {
        guard listens else { return }
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

    /// Envoie un message à la session : tapé dans son terminal, écrit dans sa conversation de
    /// l'app Claude (ou, pour un choix, clic sur son bouton), sinon collé dans son app.
    func reply(_ text: String, to sessionID: String, asChoice: Bool = false) async -> ClaudeReply.Outcome {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return .failed("Session introuvable") }
        guard session.state != .inactive, let pid = session.pid else { return .failed("Session fermée") }
        return await ClaudeReply.send(text, toProcess: pid, sessionTitle: session.title, asChoice: asChoice)
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
        case .answer(let label):
            let session = sessions.first { $0.id == permission.sessionID }
            if let pid = session?.pid, ClaudeReply.isInClaudeApp(pid) {
                // App Claude : elle affiche sa propre question ; on la laisse faire et on clique
                // sur la réponse choisie dans l'app.
                output = nil
                let title = session?.title
                Task { _ = await ClaudeReply.send(label, toProcess: pid, sessionTitle: title, asChoice: true) }
            } else {
                // Terminal : comme dans le SDK, la question reçoit sa réponse dans « answers ».
                output = ["behavior": "allow", "updatedInput": Self.answeredInput(permission.input, label: label)]
            }
        case .terminal:
            output = nil
        }

        let body = output.flatMap {
            try? JSONSerialization.data(withJSONObject: [
                "hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": $0]
            ])
        }
        permission.reply.send(body)
        remove(permission)

        if decision != .terminal {
            update(permission.sessionID) {
                $0.state = .working
                $0.detail = permission.toolName
            }
        }
    }

    typealias Decision = PendingPermission.Decision

    func handlePermission(_ event: [String: Any], reply: HookReply) {
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
            input: input,
            reply: reply
        )
        reply.onClosed = { [weak self, weak permission] in
            guard let self, let permission else { return }
            self.remove(permission)
        }
        if let last = lastToolUse[sessionID], last.tool == tool { permission.toolUseID = last.id }
        permissions.append(permission)
        startAnswerCheck()

        upsert(sessionID, cwd: cwd) { session in
            session.state = .waiting
            session.detail = "\(tool) · \(permission.summary)"
            if let path = event["transcript_path"] as? String, !path.isEmpty { session.transcriptPath = path }
        }

        let decide: @MainActor (Decision) -> Void = { [weak self, weak permission] decision in
            if let permission { self?.decide(permission, decision) }
        }
        let focus: @MainActor () -> Void = { [weak self] in self?.focus(sessionID) }
        // Question à choix : un bouton par réponse.
        let alert =
            (tool == "AskUserQuestion" ? ClaudeAlerts.question(permission, decide: decide, focus: focus) : nil)
            ?? ClaudeAlerts.permission(permission, decide: decide, focus: focus)
        permission.alertID = alert.id
        postClaudeAlert(alert, of: sessionID)
    }

    private func remove(_ permission: PendingPermission) {
        permissions.removeAll { $0 === permission }
        if let alertID = permission.alertID { alerts?.dismiss(alertID: alertID) }
        if permissions.isEmpty {
            answerCheck?.invalidate()
            answerCheck = nil
        }
    }

    /// Filet de sécurité : si l'événement « réponse donnée » de Claude Code se perd (Encoche occupé
    /// au mauvais moment), on retrouve la réponse dans la conversation et on retire la notification.
    private func startAnswerCheck() {
        guard answerCheck == nil else { return }
        answerCheck = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAnswers() }
        }
    }

    private func checkAnswers() {
        let checks = permissions.compactMap { permission -> (id: String, path: String)? in
            guard let id = permission.toolUseID,
                let path = sessions.first(where: { $0.id == permission.sessionID })?.transcriptPath
            else { return nil }
            return (id, path)
        }
        guard !checks.isEmpty else { return }
        Task { [weak self] in
            // Lecture des fichiers hors du fil principal, une fois par conversation.
            let answered = await Task.detached(priority: .utility) {
                Dictionary(grouping: checks, by: \.path).reduce(into: Set<String>()) { answered, entry in
                    guard let text = Self.transcriptTail(at: entry.key) else { return }
                    for check in entry.value where Self.containsResult(in: text, for: check.id) {
                        answered.insert(check.id)
                    }
                }
            }.value
            guard let self, !answered.isEmpty else { return }
            for permission in self.permissions where answered.contains(permission.toolUseID ?? "") {
                permission.reply.send(nil)
                self.remove(permission)
            }
        }
    }

    /// Retient l'alerte qui attend ta réponse (et retire la précédente de la session).
    private func trackWaitingAlert(_ alert: NotchAlert, of sessionID: String) {
        clearWaitingAlert(of: sessionID)
        waitingAlerts[sessionID] = alert.id
    }

    private func clearWaitingAlert(of sessionID: String) {
        if let alertID = waitingAlerts.removeValue(forKey: sessionID) { alerts?.dismiss(alertID: alertID) }
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

    func handle(_ event: [String: Any]) {
        currentPID = event["_claude_pid"] as? pid_t
        defer { currentPID = nil }
        guard let id = event["session_id"] as? String,
            let name = event["hook_event_name"] as? String
        else { return }
        let cwd = event["cwd"] as? String ?? ""
        if isAskSession(cwd) { return }

        // Tout événement qui suit montre que la demande a été tranchée ailleurs.
        if ["PreToolUse", "PostToolUse", "UserPromptSubmit", "Stop", "SessionEnd"].contains(name) {
            resolvePermissions(of: id)
            clearWaitingAlert(of: id)
        }

        if name == "SessionEnd" {
            // Gardée dans le sélecteur des dernières sessions.
            update(id) {
                $0.state = .inactive
                $0.detail = nil
                $0.pid = nil
            }
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
            upsert(id, cwd: cwd) {
                $0.state = .idle
                $0.detail = nil
            }
            readTranscript(of: id)
        case "UserPromptSubmit":
            let prompt = (event["prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            upsert(id, cwd: cwd) { session in
                session.state = .working
                session.detail = nil
                session.prompt = prompt?.isEmpty == false ? prompt : session.prompt
                session.agents = []
                session.lastMessage = nil
                session.choices = nil
                // Plan terminé : il appartenait à la demande précédente.
                if session.plan.allSatisfy({ $0.status == .completed }) { session.plan = [] }
            }
            readTranscript(of: id)
        case "PreToolUse":
            let tool = event["tool_name"] as? String ?? ""
            let input = event["tool_input"] as? [String: Any] ?? [:]
            let toolUseID = event["tool_use_id"] as? String
            if let toolUseID { lastToolUse[id] = (tool, toolUseID) }
            upsert(id, cwd: cwd) { session in
                session.state = .working
                session.detail = ClaudeActivity.describe(tool: tool, input: input)
                ClaudeActivity.applyPlan(tool: tool, input: input, to: &session.plan)
                if let choices = ClaudeActivity.suggestedReplies(tool: tool, input: input) { session.choices = choices }
                if ClaudeActivity.agentTools.contains(tool) {
                    let name =
                        (input["description"] as? String)
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
                let index =
                    session.agents.firstIndex { $0.id == toolUseID }
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
            // Déjà signalée (demande de permission en cours, ou fin de tâche à l'instant) : pas de doublon.
            guard previousState != .waiting, previousState != .done else { return }
            upsert(id, cwd: cwd) {
                $0.state = .waiting
                $0.detail = message.isEmpty ? nil : message
            }
            let project = sessions.first { $0.id == id }?.projectName ?? "Claude Code"
            let alert = ClaudeAlerts.waiting(project: project, message: message) { [weak self] in self?.focus(id) }
            trackWaitingAlert(alert, of: id)
            postClaudeAlert(alert, of: id)
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
        var session =
            sessions.first { $0.id == id }
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

    /// Notification de fin de tâche, avec le début de la réponse de Claude.
    private func announceDone(_ id: String, reply: String?) {
        Task { [weak self] in
            guard let self else { return }
            let info = await loadTranscript(of: id)
            // La session a déjà repris pendant la lecture de la transcription.
            guard let session = sessions.first(where: { $0.id == id }), session.state == .done else { return }
            let alert = ClaudeAlerts.done(
                session, reply: reply ?? info?.lastMessage,
                choose: { [weak self] option in self?.sendChoice(option, to: id) },
                focus: { [weak self] in self?.focus(id) })
            // Réponses proposées : retirée si tu réponds directement dans Claude.
            if !alert.buttons.isEmpty { trackWaitingAlert(alert, of: id) }
            postClaudeAlert(alert, of: id)
        }
    }

    /// Une seule notification par événement : celles de l'app Claude (relayées comme toutes les
    /// notifications du Mac) disent la même chose, on les ignore un moment.
    /// Pas de notification quand tu es déjà dans l'app de la session (app Claude, terminal).
    private func postClaudeAlert(_ alert: NotchAlert, of sessionID: String) {
        alerts?.muteRelayedNotifications(from: ClaudeReply.claudeAppID)
        guard !isSessionAppInFront(sessions.first { $0.id == sessionID }?.pid) else { return }
        alerts?.post(alert)
    }

    /// L'app qui fait tourner ce processus est au premier plan (l'app Claude, à défaut de processus connu).
    private static func isAppInFront(_ pid: pid_t?) -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return false }
        if let pid, let app = ProcessOwner.app(of: pid) {
            return app.processIdentifier == frontmost.processIdentifier
        }
        return frontmost.bundleIdentifier == ClaudeReply.claudeAppID
    }

    /// Envoie la réponse choisie dans la notification à la session.
    private func sendChoice(_ option: String, to id: String) {
        Task {
            let outcome = await reply(option, to: id, asChoice: true)
            if case .pasted(let app) = outcome {
                alerts?.post(
                    NotchAlert(
                        icon: .symbol("doc.on.clipboard.fill", .claude),
                        source: "Claude Code",
                        title: "« \(option) » collé dans \(app)",
                        body: "Appuie sur Entrée pour l'envoyer."
                    ))
            } else if case .failed(let reason) = outcome {
                alerts?.post(
                    NotchAlert(icon: .symbol("exclamationmark.triangle.fill", .orange), source: "Claude Code", title: reason, body: nil))
            }
        }
    }

    private func readTranscript(of id: String) {
        Task { await loadTranscript(of: id) }
    }

    /// Relit le titre de la session, sa dernière demande et la dernière réponse de Claude dans
    /// la transcription, et les range dans la session.
    @discardableResult
    private func loadTranscript(of id: String) async -> ClaudeTranscript.Info? {
        guard let path = sessions.first(where: { $0.id == id })?.transcriptPath else { return nil }
        let info = await ClaudeTranscript.read(path: path)
        update(id) { session in
            if let title = info.title { session.title = title }
            if session.prompt == nil { session.prompt = info.lastPrompt }
            if let message = info.lastMessage, session.state != .working { session.lastMessage = message }
        }
        return info
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
