import Foundation
import Testing

@testable import Encoche

/// Claude plus actif : demandes préparées par l'encoche, nouvelles sessions, bilan de fin de tâche.
struct ClaudePromptsTests {
    @Test func errorsAreDebuggedFirst() {
        let trace = "Traceback (most recent call last):\n  File \"a.py\", line 3\nKeyError: 'x'"
        #expect(ClaudePrompts.looksLikeError(trace))
        #expect(ClaudePrompts.textActions(for: trace).first == .debug)
        #expect(ClaudePrompts.textActions(for: "Bonjour à tous") == [.explain, .translate, .fix])
    }

    @Test func textRequestsShowAShortLabel() {
        let request = ClaudePrompts.text(.translate, String(repeating: "mot ", count: 50))
        #expect(request.label.hasPrefix("Traduire « mot mot"))
        #expect(request.label.count < 60)
        #expect(request.prompt.contains("Traduis"))
        #expect(request.files.isEmpty)
    }

    @Test func imagesAndFilesAreReadable() {
        let shot = URL(fileURLWithPath: "/tmp/Capture.png")
        #expect(ClaudePrompts.file(shot).label == "Décrire Capture.png")
        #expect(ClaudePrompts.file(shot).files == [shot])
        let doc = URL(fileURLWithPath: "/tmp/notes.pdf")
        #expect(ClaudePrompts.file(doc).label == "Résumer notes.pdf")
        #expect(ClaudeAsk.toolArguments(for: []) == ["--tools", ""])
        #expect(ClaudeAsk.toolArguments(for: [shot, doc]) == ["--tools", "Read", "--allowedTools", "Read", "--add-dir", "/tmp"])
    }

    @Test func meetingPromptHasItsDetails() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let meeting = ClaudePrompts.Meeting(
            title: "Point produit", start: start, end: start.addingTimeInterval(1800), location: "Salle 2",
            notes: "Roadmap T1", attendees: ["Alice", "Bob"])
        let request = ClaudePrompts.meeting(meeting)
        #expect(request.label == "Préparer « Point produit »")
        #expect(request.prompt.contains("Participants : Alice, Bob"))
        #expect(request.prompt.contains("Roadmap T1"))
    }

    @Test func briefingListsTheDay() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var day = ClaudePrompts.Briefing()
        #expect(day.isEmpty)
        day.events = [.init(title: "Daily", start: start, end: start.addingTimeInterval(900))]
        day.tasks = ["Revoir la maquette (en retard) · Design"]
        let request = ClaudePrompts.briefing(day, date: start)
        #expect(request.label.hasPrefix("Briefing du "))
        #expect(request.prompt.contains("Daily"))
        #expect(request.prompt.contains("Tâches ClickUp :\n- Revoir la maquette"))
        #expect(!request.prompt.contains("Rappels :"))
    }

    @Test func notificationsAreCapped() {
        let lines = (1...50).map {
            ClaudePrompts.NotificationLine(source: "Mail", title: "Message \($0)", body: nil, date: Date())
        }
        let request = ClaudePrompts.notifications(lines)
        #expect(request.label == "Résumer 40 notifications")
        #expect(!request.prompt.contains("Message 41"))
    }

    @Test func briefingIsOnceAMorning() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 8))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 19))!
        #expect(ClaudeBriefing.isDue(now: morning, lastDay: nil, calendar: calendar))
        #expect(!ClaudeBriefing.isDue(now: evening, lastDay: nil, calendar: calendar))
        let today = ClaudeBriefing.dayKey(morning, calendar: calendar)
        #expect(!ClaudeBriefing.isDue(now: morning, lastDay: today, calendar: calendar))
    }

    @Test func newSessionCommandIsQuoted() {
        let command = ClaudeReply.sessionCommand(
            prompt: "Corrige l'erreur", in: "/Users/me/My App", cli: URL(fileURLWithPath: "/opt/homebrew/bin/claude"))
        #expect(command == "cd '/Users/me/My App' && '/opt/homebrew/bin/claude' 'Corrige l'\\''erreur'")
        #expect(ClaudeReply.sessionCommand(prompt: "", in: "/p", cli: nil) == "cd '/p' && claude")
    }

    @Test func testCommandsAndFailures() {
        #expect(ClaudeActivity.isTestCommand("./scripts/test.sh 2>&1 | tail"))
        #expect(ClaudeActivity.isTestCommand("xcodebuild -scheme Notch test"))
        #expect(!ClaudeActivity.isTestCommand("xcodebuild -scheme Notch build"))
        #expect(!ClaudeActivity.isTestCommand("git status"))
        #expect(ClaudeActivity.didFail("Error: file not found"))
        #expect(ClaudeActivity.didFail(["stdout": "…\nExit code 1"]))
        #expect(ClaudeActivity.didFail(["is_error": true]))
        #expect(!ClaudeActivity.didFail(["stdout": "ok", "stderr": ""]))
        #expect(!ClaudeActivity.didFail(["stdout": "Exit code 0"]))
    }
}

@MainActor
struct ClaudeSessionReactionTests {
    private let monitor = ClaudeCodeMonitor(listens: false)
    private let alerts = AlertCenter(historyURL: nil)

    init() {
        monitor.alerts = alerts
        monitor.isSessionAppInFront = { _ in false }
    }

    private func send(_ name: String, session: String = "s1", cwd: String = "/p/Encoche", _ extra: [String: Any] = [:]) {
        var event: [String: Any] = ["hook_event_name": name, "session_id": session, "cwd": cwd]
        event.merge(extra) { $1 }
        monitor.handle(event)
    }

    private var session: ClaudeCodeSession? { monitor.sessions.first { $0.id == "s1" } }

    @Test func doneAlertSumsUpTheChanges() async throws {
        send("UserPromptSubmit", ["prompt": "Go"])
        let edit: [String: Any] = ["file_path": "/p/A.swift", "old_string": "a", "new_string": "b\nc"]
        send("PostToolUse", ["tool_name": "Edit", "tool_input": edit])
        send("PostToolUse", ["tool_name": "Write", "tool_input": ["file_path": "/p/B.swift", "content": "x"]])
        send("PreToolUse", ["tool_name": "Bash", "tool_input": ["command": "swift test"]])
        #expect(session?.testsPassed == false)
        send("PostToolUse", ["tool_name": "Bash", "tool_input": ["command": "swift test"], "tool_response": ["stdout": "ok"]])
        #expect(session?.changeSummary == "2 fichiers modifiés · +3 −1 · tests OK")

        send("Stop", ["last_assistant_message": "C'est fait."])
        #expect(monitor.isCelebrating)
        #expect(monitor.mood(of: session!) == .celebrating)
        for _ in 0..<50 where alerts.current == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(alerts.current?.body == "2 fichiers modifiés · +3 −1 · tests OK — C'est fait.")

        send("UserPromptSubmit", ["prompt": "Encore"])
        #expect(session?.editedFiles.isEmpty == true)
        #expect(session?.changeSummary == nil)
    }

    @Test func failedToolWorriesTheMascot() {
        send("PreToolUse", ["tool_name": "Bash", "tool_input": ["command": "make"]])
        #expect(monitor.mood(of: session!) == .working)
        send("PostToolUse", ["tool_name": "Bash", "tool_input": ["command": "make"], "tool_response": "Error: boom"])
        #expect(monitor.mood(of: session!) == .worried)
    }

    @Test func recentProjectsAreUnique() {
        send("PreToolUse", session: "a", cwd: "/p/One", ["tool_name": "Bash"])
        send("PreToolUse", session: "b", cwd: "/p/Two", ["tool_name": "Bash"])
        send("PreToolUse", session: "c", cwd: "/p/One", ["tool_name": "Bash"])
        #expect(Set(monitor.recentProjects) == ["/p/One", "/p/Two"])
        #expect(monitor.recentProjects.count == 2)
    }
}

/// « Toujours » quand Claude Code ne suggère pas de règle.
struct ClaudePermissionRulesTests {
    @Test func bashKeepsCommandAndSubcommand() {
        #expect(ClaudePermissionRules.commandPrefix("npm test -- --watch") == "npm test")
        #expect(ClaudePermissionRules.commandPrefix("git push origin main") == "git push")
        #expect(ClaudePermissionRules.commandPrefix("ls -la") == "ls")
        #expect(ClaudePermissionRules.commandPrefix("FOO=1 swift build && echo ok") == "swift build")
        #expect(ClaudePermissionRules.commandPrefix("git -C x status") == "git")
    }

    @Test func riskyCommandsAreNeverAlwaysAllowed() {
        #expect(ClaudePermissionRules.commandPrefix("rm -rf build") == nil)
        #expect(ClaudePermissionRules.commandPrefix("sudo make install") == nil)
        #expect(ClaudePermissionRules.rule(tool: "Bash", input: ["command": "rm x"]) == nil)
    }

    @Test func rulesForOtherTools() {
        #expect(
            ClaudePermissionRules.rule(tool: "WebFetch", input: ["url": "https://docs.swift.org/x"])
                == .init(toolName: "WebFetch", content: "domain:docs.swift.org"))
        #expect(ClaudePermissionRules.rule(tool: "Edit", input: [:]) == .init(toolName: "Edit", content: nil))
        #expect(ClaudePermissionRules.rule(tool: "AskUserQuestion", input: [:]) == nil)
    }

    @Test func describesUpdates() {
        let update = ClaudePermissionRules.update(for: .init(toolName: "Bash", content: "npm test:*"))
        #expect(ClaudePermissionRules.describe([update]) == "Bash(npm test:*)")
        #expect(update["destination"] as? String == "localSettings")
    }
}
