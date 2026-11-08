import Foundation
import Network
import Testing

@testable import Encoche

/// Événements des hooks Claude Code : état des sessions, notifications et demandes de permission.
@MainActor
struct ClaudeCodeMonitorTests {
    private let monitor: ClaudeCodeMonitor
    private let alerts = AlertCenter(historyURL: nil)

    init() {
        monitor = ClaudeCodeMonitor(listens: false)
        monitor.alerts = alerts
        monitor.isSessionAppInFront = { _ in false }
    }

    private func send(_ name: String, session: String = "s1", cwd: String = "/p/Encoche", _ extra: [String: Any] = [:]) {
        var event: [String: Any] = ["hook_event_name": name, "session_id": session, "cwd": cwd]
        event.merge(extra) { $1 }
        monitor.handle(event)
    }

    private func state(of id: String = "s1") -> ClaudeCodeSession.State? {
        monitor.sessions.first { $0.id == id }?.state
    }

    /// Réponse à une demande de permission (connexion jamais ouverte : rien n'est envoyé).
    private func reply() -> HookReply {
        HookReply(connection: NWConnection(host: "127.0.0.1", port: 9, using: .tcp))
    }

    /// Attend la notification de fin de tâche, postée après la lecture de la transcription.
    private func waitForAlert() async throws {
        for _ in 0..<50 where alerts.current == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func toolUseShowsWhatClaudeDoes() {
        send("PreToolUse", ["tool_name": "Edit", "tool_input": ["file_path": "/a/HomeView.swift"]])
        #expect(state() == .working)
        #expect(monitor.sessions.first?.detail == "Modifie HomeView.swift")
        #expect(monitor.sessions.first?.projectName == "Encoche")
        #expect(monitor.workingSession?.id == "s1")
    }

    @Test func waitingAlertIsRemovedWhenTheSessionResumes() {
        send("PreToolUse", ["tool_name": "Bash"])
        send("Notification", ["message": "Claude needs your permission"])
        #expect(state() == .waiting)
        #expect(monitor.needsAttention)
        #expect(alerts.current?.title == "Encoche t'attend")

        send("PreToolUse", ["tool_name": "Bash"])
        #expect(state() == .working)
        #expect(alerts.current == nil)
    }

    @Test func idleReminderIsNotAnAlert() {
        send("Notification", ["message": "Claude is waiting for your input", "notification_type": "idle_prompt"])
        #expect(alerts.current == nil)
    }

    @Test func noAlertWhileTheSessionAppIsInFront() {
        monitor.isSessionAppInFront = { _ in true }
        send("Notification", ["message": "Besoin de toi"])
        #expect(state() == .waiting)
        #expect(alerts.current == nil)
    }

    @Test func stopAnnouncesTheEndOfTheTask() async throws {
        send("UserPromptSubmit", ["prompt": "  Fais le ménage  "])
        #expect(monitor.sessions.first?.prompt == "Fais le ménage")
        send("Stop", ["last_assistant_message": "**C'est fait** !"])
        #expect(state() == .done)
        try await waitForAlert()
        #expect(alerts.current?.title == "Terminé · Encoche")
        #expect(alerts.current?.body == "C'est fait !")
    }

    @Test func suggestedRepliesBecomeButtonsUntilYouAnswer() async throws {
        send(
            "PreToolUse",
            [
                "tool_name": "mcp__ccd_turn__wrap_up",
                "tool_input": [
                    "ask": "On publie ?", "actions": [["label": "Oui"], ["label": "Non"]],
                ],
            ])
        send("Stop")
        try await waitForAlert()
        #expect(alerts.current?.title == "Encoche te demande")
        #expect(alerts.current?.buttons.map(\.label) == ["Plus tard", "Oui", "Non"])

        // Réponse donnée directement dans Claude.
        send("UserPromptSubmit", ["prompt": "Oui"])
        #expect(alerts.current == nil)
        #expect(monitor.sessions.first?.choices == nil)
    }

    @Test func noEndAlertWhenTheSessionAlreadyResumed() async throws {
        send("Stop")
        send("UserPromptSubmit", ["prompt": "Autre chose"])
        try await Task.sleep(for: .milliseconds(200))
        #expect(alerts.current == nil)
    }

    @Test func sessionEndKeepsTheSessionAsInactive() {
        send("PreToolUse", ["tool_name": "Bash", "_claude_pid": pid_t(1234)])
        #expect(monitor.sessions.first?.pid == 1234)
        send("SessionEnd")
        #expect(state() == .inactive)
        #expect(monitor.sessions.first?.pid == nil)
    }

    @Test func onlyRecentInactiveSessionsAreKept() {
        for index in 0..<7 {
            send("PreToolUse", session: "s\(index)", ["tool_name": "Bash"])
            send("SessionEnd", session: "s\(index)")
        }
        send("PreToolUse", session: "live", ["tool_name": "Bash"])
        #expect(monitor.sessions.count == ClaudeCodeMonitor.recentLimit)
        #expect(monitor.sessions.contains { $0.id == "live" })
        #expect(monitor.sortedSessions.last?.state == .inactive)
    }

    @Test func quickQuestionsAreNotListed() {
        send("PreToolUse", cwd: ClaudeAsk.workingDirectory.path, ["tool_name": "Bash"])
        #expect(monitor.sessions.isEmpty)
    }

    @Test func waitingSessionsComeFirst() {
        send("PreToolUse", session: "a", ["tool_name": "Bash"])
        send("Notification", session: "b", ["message": "?"])
        send("PreToolUse", session: "c", ["tool_name": "Bash"])
        #expect(monitor.sortedSessions.map(\.id) == ["b", "c", "a"])
        #expect(monitor.waitingCount == 1)
    }

    // MARK: - Permissions

    private func askPermission(
        _ tool: String = "Bash", input: [String: Any] = ["command": "rm -rf build"],
        suggestions: [[String: Any]] = []
    ) {
        monitor.handlePermission(
            [
                "session_id": "s1", "cwd": "/p/Encoche", "tool_name": tool, "tool_input": input,
                "permission_suggestions": suggestions,
            ], reply: reply())
    }

    @Test func permissionRequestWaitsForYourDecision() {
        askPermission(suggestions: [["type": "addRules"]])
        #expect(state() == .waiting)
        #expect(monitor.permission(for: "s1") != nil)
        #expect(alerts.current?.title == "Encoche demande : Bash")
        #expect(alerts.current?.buttons.map(\.label) == ["Refuser", "Terminal", "Toujours", "Autoriser"])

        let permission = try! #require(monitor.permission(for: "s1"))
        monitor.decide(permission, .allow)
        #expect(monitor.permissions.isEmpty)
        #expect(alerts.current == nil)
        #expect(state() == .working)
    }

    @Test func permissionAnsweredElsewhereIsWithdrawn() {
        askPermission()
        #expect(alerts.current?.buttons.map(\.label) == ["Refuser", "Terminal", "Autoriser"])
        send("PostToolUse", ["tool_name": "Bash"])
        #expect(monitor.permissions.isEmpty)
        #expect(alerts.current == nil)
    }

    @Test func singleQuestionGetsOneButtonPerAnswer() {
        askPermission(
            "AskUserQuestion",
            input: [
                "questions": [
                    [
                        "question": "Laquelle ?", "options": [["label": "A"], ["label": "B"]],
                    ]
                ]
            ])
        #expect(alerts.current?.title == "Encoche te demande")
        #expect(alerts.current?.body == "Laquelle ?")
        #expect(alerts.current?.buttons.map(\.label) == ["Autre…", "A", "B"])
    }

    @Test func terminalChoiceKeepsTheSessionWaiting() {
        askPermission()
        let permission = try! #require(monitor.permission(for: "s1"))
        monitor.decide(permission, .terminal)
        #expect(monitor.permissions.isEmpty)
        #expect(state() == .waiting)
    }
}

/// Lecture des requêtes HTTP envoyées par les hooks.
struct HookServerTests {
    private func request(_ body: String, path: String = "/claude-code", method: String = "POST", length: Int? = nil) -> Data {
        let size = length ?? body.utf8.count
        return Data("\(method) \(path) HTTP/1.1\r\nHost: x\r\nX-Claude-PID: 42\r\nContent-Length: \(size)\r\n\r\n\(body)".utf8)
    }

    @Test func completeRequest() throws {
        let (path, headers, body) = try #require(HookServer.parse(request(#"{"a":1}"#)))
        #expect(path == "/claude-code")
        #expect(headers[HookServer.pidHeader.lowercased()] == "42")
        #expect(String(decoding: body, as: UTF8.self) == #"{"a":1}"#)
    }

    @Test func waitsForTheWholeBody() {
        #expect(HookServer.parse(request("{", length: 10)) == nil)
        #expect(HookServer.parse(Data("POST /claude-code HTTP/1.1\r\nContent-Length: 2".utf8)) == nil)
    }

    @Test func ignoresOtherMethods() throws {
        let (path, _, body) = try #require(HookServer.parse(request("", method: "GET")))
        #expect(path.isEmpty)
        #expect(body.isEmpty)
    }
}

/// Contenu des notifications Claude.
@MainActor
struct ClaudeAlertsTests {
    private func session(title: String? = nil, choices: ClaudeCodeSession.Choices? = nil) -> ClaudeCodeSession {
        var session = ClaudeCodeSession(id: "s", cwd: "/p/Encoche", state: .done, detail: nil, updatedAt: .now)
        session.title = title
        session.choices = choices
        return session
    }

    @Test func doneUsesTheSessionTitle() {
        let alert = ClaudeAlerts.done(session(title: "Ménage"), reply: "## Fait", choose: { _ in }, focus: {})
        #expect(alert.title == "Terminé · Ménage")
        #expect(alert.body == "Fait")
        #expect(alert.source == "Encoche")
        #expect(alert.buttons.isEmpty)
    }

    @Test func doneOffersAtMostThreeReplies() {
        var chosen: String?
        let choices = ClaudeCodeSession.Choices(question: "Laquelle ?", options: ["A", "B", "C", "D"])
        let alert = ClaudeAlerts.done(session(choices: choices), reply: nil, choose: { chosen = $0 }, focus: {})
        #expect(alert.title == "Encoche te demande")
        #expect(alert.buttons.map(\.label) == ["Plus tard", "A", "B", "C"])
        alert.buttons[2].action()
        #expect(chosen == "B")
    }

    @Test func permissionButtonsDecide() throws {
        var decisions: [PendingPermission.Decision] = []
        var focused = false
        let permission = PendingPermission(
            sessionID: "s", projectName: "Encoche", toolName: "Bash", summary: "ls", suggestions: [],
            reply: HookReply(connection: NWConnection(host: "127.0.0.1", port: 9, using: .tcp)))
        let alert = ClaudeAlerts.permission(permission, decide: { decisions.append($0) }, focus: { focused = true })
        for button in alert.buttons { button.action() }
        #expect(decisions == [.deny, .terminal, .allow])
        if case .run(let block) = alert.action { block() }
        #expect(focused)
    }

    @Test func multipleQuestionsStayInTheTerminal() {
        let permission = PendingPermission(
            sessionID: "s", projectName: "Encoche", toolName: "AskUserQuestion", summary: "", suggestions: [],
            input: ["questions": [["question": "1", "options": [["label": "A"]]], ["question": "2", "options": [["label": "B"]]]]],
            reply: HookReply(connection: NWConnection(host: "127.0.0.1", port: 9, using: .tcp)))
        #expect(ClaudeAlerts.question(permission, decide: { _ in }, focus: {}) == nil)
    }
}
