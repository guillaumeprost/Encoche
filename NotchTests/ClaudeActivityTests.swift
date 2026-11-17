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
        ClaudeActivity.applyPlan(
            tool: "TodoWrite",
            input: [
                "todos": [
                    ["content": "Écrire", "status": "completed"],
                    ["content": "Tester", "activeForm": "Teste", "status": "in_progress"],
                    ["content": "Publier", "status": "pending"],
                ]
            ], to: &plan)
        #expect(plan.map(\.content) == ["Écrire", "Teste", "Publier"])
        #expect(plan.map(\.status) == [.completed, .inProgress, .pending])
    }

    @Test func updatePlanAdvancesAndJumps() {
        var plan: [ClaudeCodeSession.PlanItem] = []
        ClaudeActivity.applyPlan(
            tool: "mcp__ccd_turn__update_plan",
            input: [
                "items": [
                    ["content": "A", "status": "in_progress"], ["content": "B", "status": "pending"],
                    ["content": "C", "status": "pending"],
                ]
            ], to: &plan)
        ClaudeActivity.applyPlan(tool: "mcp__ccd_turn__update_plan", input: ["advance": true], to: &plan)
        #expect(plan.map(\.status) == [.completed, .inProgress, .pending])
        ClaudeActivity.applyPlan(tool: "mcp__ccd_turn__update_plan", input: ["done": [2], "start": 3], to: &plan)
        #expect(plan.map(\.status) == [.completed, .completed, .inProgress])
    }

    @Test func suggestedRepliesIgnoreAppActions() {
        let choices = ClaudeActivity.suggestedReplies(
            tool: "mcp__ccd_turn__wrap_up",
            input: [
                "ask": "On publie ?",
                "actions": [["label": "Oui"], ["label": "Commit", "action": "commit"], ["label": "Non"]],
            ])
        #expect(choices?.question == "On publie ?")
        #expect(choices?.options == ["Oui", "Non"])
        #expect(ClaudeActivity.suggestedReplies(tool: "mcp__ccd_turn__wrap_up", input: ["recap": "ok"]) == nil)
        #expect(ClaudeActivity.suggestedReplies(tool: "Bash", input: ["ask": "?"]) == nil)
    }

    @Test func suggestedRepliesAcceptJSONStrings() {
        let choices = ClaudeActivity.suggestedReplies(
            tool: "mcp__ccd_turn__wrap_up",
            input: [
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

    // MARK: - Aperçu des modifications

    @Test func editDiffKeepsOnlyChangedLines() {
        let input: [String: Any] = ["old_string": "a\nb\nc", "new_string": "a\nB\nB2\nc"]
        let diff = ClaudeActivity.diff(tool: "Edit", input: input)
        #expect(diff?.map(\.kind) == [.removed, .added, .added])
        #expect(diff?.map(\.text) == ["b", "B", "B2"])
        #expect(ClaudeActivity.summarize(tool: "Edit", input: input.merging(["file_path": "/x/A.swift"]) { $1 }) == "A.swift · +2 −1")
    }

    @Test func longWriteIsCutWithACount() {
        let content = (1...20).map(String.init).joined(separator: "\n")
        let diff = ClaudeActivity.diff(tool: "Write", input: ["content": content], limit: 5)
        #expect(diff?.count == 6)
        #expect(diff?.last?.kind == .more)
        #expect(diff?.last?.text == "15 lignes de plus")
        #expect(ClaudeActivity.diff(tool: "Bash", input: ["command": "ls"]) == nil)
    }

    // MARK: - Interruption, durée, consommation, quotas

    @Test func interruptionIsTheLastExchange() {
        let interrupted = """
            {"type":"assistant","message":{"content":[{"type":"text","text":"Je regarde"}]}}
            {"type":"user","message":{"content":[{"type":"text","text":"[Request interrupted by user]"}]}}
            {"type":"system","content":"x"}
            """
        #expect(ClaudeCodeMonitor.endsWithInterruption(interrupted))
        let resumed = interrupted + "\n" + #"{"type":"assistant","message":{"content":[{"type":"text","text":"Ok"}]}}"#
        #expect(!ClaudeCodeMonitor.endsWithInterruption(resumed))
        let toolUse = #"{"type":"user","message":{"content":"[Request interrupted by user for tool use]"}}"#
        #expect(ClaudeCodeMonitor.endsWithInterruption(toolUse))
    }

    @Test func elapsedTimeReadsNaturally() {
        let start = Date(timeIntervalSince1970: 0)
        #expect(ClaudeCodeSession.elapsed(since: start, now: start.addingTimeInterval(42)) == "42 s")
        #expect(ClaudeCodeSession.elapsed(since: start, now: start.addingTimeInterval(185)) == "3 min")
        #expect(ClaudeCodeSession.elapsed(since: start, now: start.addingTimeInterval(3900)) == "1 h 05")
    }

    @Test func modelNamesAreShort() {
        #expect(ClaudeUsage.modelName("claude-opus-4-5-20251101") == "Opus 4.5")
        #expect(ClaudeUsage.modelName("claude-haiku-4-5") == "Haiku 4.5")
        #expect(ClaudeUsage.modelName("claude-3-5-sonnet-20241022") == "Sonnet 3.5")
        #expect(ClaudeUsage.modelName("<synthetic>") == nil)
    }

    @Test func usageIsRankedAcrossDays() {
        let ranked = ClaudeUsage.ranked([["A": .init(output: 5)], ["B": .init(output: 8), "A": .init(output: 4)]])
        #expect(ranked.map(\.name) == ["A", "B"])
        #expect(ranked.first?.totals.output == 9)
    }

    @Test func quotaLevels() {
        #expect(ClaudeQuota.level(for: 0.5) == nil)
        #expect(ClaudeQuota.level(for: 0.85) == 0.8)
        #expect(ClaudeQuota.level(for: 0.97) == 0.95)
    }
}
