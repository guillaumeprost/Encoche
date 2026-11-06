import Foundation
import Testing
@testable import Encoche

/// Traduction des outils de Claude Code, plan, réponses proposées et transcriptions.
struct ClaudeActivityTests {
    @Test func describesCommonTools() {
        #expect(ClaudeActivity.describe(tool: "Edit", input: ["file_path": "/a/b/HomeView.swift"]) == "Modifie HomeView.swift")
        #expect(ClaudeActivity.describe(tool: "Read", input: ["file_path": "/x/README.md"]) == "Lit README.md")
        #expect(ClaudeActivity.describe(tool: "Grep", input: ["pattern": "refresh"]) == "Cherche « refresh »")
        #expect(ClaudeActivity.describe(tool: "WebFetch", input: ["url": "https://lrclib.net/api"]) == "Lit lrclib.net")
        #expect(ClaudeActivity.describe(tool: "mcp__ccd_turn__update_plan", input: [:]) == "Met à jour son plan")
        #expect(ClaudeActivity.describe(tool: "mcp__github__create_issue", input: [:]) == "Utilise create issue")
    }

    @Test func bashPrefersItsDescription() {
        #expect(ClaudeActivity.describe(tool: "Bash", input: ["command": "ls", "description": "List files"]) == "List files")
        #expect(ClaudeActivity.describe(tool: "Bash", input: ["command": "ls -la"]) == "Lance ls -la")
    }

    @Test func summaryIsShortAndSingleLine() {
        let long = String(repeating: "a", count: 300)
        let summary = ClaudeActivity.summarize(tool: "Bash", input: ["command": "echo\n" + long])
        #expect(!summary.contains("\n"))
        #expect(summary.count <= 141)
        #expect(summary.hasSuffix("…"))
    }

    @Test func todoWriteReplacesThePlan() {
        var plan: [ClaudeCodeSession.PlanItem] = []
        ClaudeActivity.applyPlan(tool: "TodoWrite", input: ["todos": [
            ["content": "Écrire", "status": "completed"],
            ["content": "Tester", "activeForm": "Teste", "status": "in_progress"],
            ["content": "Publier", "status": "pending"],
        ]], to: &plan)
        #expect(plan.map(\.content) == ["Écrire", "Teste", "Publier"])
        #expect(plan.map(\.status) == [.completed, .inProgress, .pending])
    }

    @Test func updatePlanAdvancesAndJumps() {
        var plan: [ClaudeCodeSession.PlanItem] = []
        ClaudeActivity.applyPlan(tool: "mcp__ccd_turn__update_plan", input: ["items": [
            ["content": "A", "status": "in_progress"], ["content": "B", "status": "pending"], ["content": "C", "status": "pending"],
        ]], to: &plan)
        ClaudeActivity.applyPlan(tool: "mcp__ccd_turn__update_plan", input: ["advance": true], to: &plan)
        #expect(plan.map(\.status) == [.completed, .inProgress, .pending])
        ClaudeActivity.applyPlan(tool: "mcp__ccd_turn__update_plan", input: ["done": [2], "start": 3], to: &plan)
        #expect(plan.map(\.status) == [.completed, .completed, .inProgress])
    }

    @Test func suggestedRepliesIgnoreAppActions() {
        let choices = ClaudeActivity.suggestedReplies(tool: "mcp__ccd_turn__wrap_up", input: [
            "ask": "On publie ?",
            "actions": [["label": "Oui"], ["label": "Commit", "action": "commit"], ["label": "Non"]],
        ])
        #expect(choices?.question == "On publie ?")
        #expect(choices?.options == ["Oui", "Non"])
        #expect(ClaudeActivity.suggestedReplies(tool: "mcp__ccd_turn__wrap_up", input: ["recap": "ok"]) == nil)
        #expect(ClaudeActivity.suggestedReplies(tool: "Bash", input: ["ask": "?"]) == nil)
    }

    @Test func suggestedRepliesAcceptJSONStrings() {
        let choices = ClaudeActivity.suggestedReplies(tool: "mcp__ccd_turn__wrap_up", input: [
            "ask": "Quoi ?", "actions": #"[{"label": "A"}, {"label": "B"}]"#,
        ])
        #expect(choices?.options == ["A", "B"])
    }

    @Test func transcriptGivesTitlePromptAndLastReply() async throws {
        let lines = [
            #"{"type":"user","cwd":"/Users/me/Projects/Encoche","message":{"content":"Bonjour"}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Première réponse"}]}}"#,
            #"{"type":"assistant","isSidechain":true,"message":{"content":[{"type":"text","text":"Réponse d'un agent"}]}}"#,
            #"{"type":"custom-title","customTitle":"Ma session"}"#,
            #"{"type":"last-prompt","lastPrompt":"Bonjour"}"#,
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("encoche-test-\(UUID().uuidString).jsonl")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let info = await ClaudeTranscript.read(path: url.path)
        #expect(info.title == "Ma session")
        #expect(info.lastPrompt == "Bonjour")
        #expect(info.lastMessage == "Première réponse")
        #expect(info.cwd == "/Users/me/Projects/Encoche")
    }

    @Test func plainSummaryDropsMarkdown() {
        let text = "## Titre\n\n- **Gras** et `code`\n```swift\nlet a = 1\n```\nFin"
        let summary = ClaudeCodeMonitor.plainSummary(text)
        #expect(!summary.contains("**"))
        #expect(!summary.contains("`"))
        #expect(!summary.contains("#"))
        #expect(summary.hasPrefix("Titre Gras et code"))
    }

    @Test func sessionHelpers() {
        #expect(ClaudeCodeSession.projectName(for: "/Users/me/Projects/Encoche") == "Encoche")
        #expect(ClaudeCodeSession.projectName(for: "") == "Claude Code")
        var session = ClaudeCodeSession(id: "1", cwd: "/a", state: .working, detail: nil, updatedAt: .now)
        #expect(session.planFraction == nil)
        session.plan = [.init(id: 0, content: "A", status: .completed), .init(id: 1, content: "B", status: .pending)]
        #expect(session.planFraction == 0.5)
    }
}

struct QuestionAnsweredElsewhereTests {
    @Test func findsToolResultForTheQuestion() {
        let transcript = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_A","name":"AskUserQuestion"}]}}
        {"type":"user","message":{"content":[{"tool_use_id":"toolu_A","type":"tool_result","content":"Oui"}]}}
        """
        #expect(ClaudeCodeMonitor.containsResult(in: transcript, for: "toolu_A"))
    }

    @Test func ignoresTheQuestionItselfAndOtherResults() {
        let transcript = """
        {"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_A","name":"AskUserQuestion"}]}}
        {"type":"user","message":{"content":[{"tool_use_id":"toolu_B","type":"tool_result","content":"ok"}]}}
        """
        #expect(!ClaudeCodeMonitor.containsResult(in: transcript, for: "toolu_A"))
    }
}
