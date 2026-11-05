import Foundation
import Testing
@testable import Encoche

/// Réponses à Claude, questions, quotas, file d'attente et « À l'écoute ».
struct RepliesAndPlayersTests {
    @Test func messagesStayOnOneLine() {
        #expect(ClaudeReply.sanitized("  Bonjour\nà toi\r\n ") == "Bonjour à toi")
        #expect(ClaudeReply.sanitized("\n").isEmpty)
    }

    @Test func choicesMatchButtonsAndQuestionBoxes() {
        // Bouton de réponse proposée : libellé exact.
        #expect(ClaudeReply.matchesChoice(role: "AXButton", title: "Oui", label: "Oui"))
        #expect(!ClaudeReply.matchesChoice(role: "AXButton", title: "Oui, parfait", label: "Oui"))
        // Case de question : « libellé description ».
        #expect(ClaudeReply.matchesChoice(role: "AXCheckBox", title: "Prêt J'ai attendu 10 secondes", label: "Prêt"))
        #expect(!ClaudeReply.matchesChoice(role: "AXCheckBox", title: "Prêtes à partir", label: "Prêt"))
    }

    @Test func conversationTitles() {
        #expect(ClaudeReply.matchesConversation(shown: "Notchnook application - Claude Code", title: "Notchnook application"))
        #expect(ClaudeReply.matchesConversation(shown: "Notchnook application", title: "Notchnook application"))
        #expect(!ClaudeReply.matchesConversation(shown: "Notchnook application v2 - Claude Code", title: "Notchnook application"))
    }

    @Test func appleScriptEscaping() {
        #expect(AppleScriptRunner.escape(#"Il a dit "oui" \o/"#) == #"Il a dit \"oui\" \\o/"#)
    }

    @Test func singleQuestionsOnly() {
        let input: [String: Any] = ["questions": [[
            "question": "Laquelle ?", "multiSelect": false,
            "options": [["label": "A"], ["label": "B"], ["label": "C"], ["label": "D"], ["label": "E"]],
        ]]]
        let question = ClaudeCodeMonitor.singleQuestion(in: input)
        #expect(question?.text == "Laquelle ?")
        #expect(question?.options == ["A", "B", "C", "D"])
        #expect(ClaudeCodeMonitor.singleQuestion(in: ["questions": [["question": "?", "multiSelect": true, "options": [["label": "A"]]]]]) == nil)
        #expect(ClaudeCodeMonitor.singleQuestion(in: ["questions": [["question": "1", "options": []], ["question": "2", "options": []]]]) == nil)
    }

    @Test func answersAreAddedToTheQuestion() {
        let input: [String: Any] = ["questions": [["question": "Laquelle ?", "options": []]]]
        let answered = ClaudeCodeMonitor.answeredInput(input, label: "B")
        #expect((answered["answers"] as? [String: String]) == ["Laquelle ?": "B"])
        #expect(answered["questions"] != nil)
    }

    @Test func quotaLimits() {
        let limit = ClaudeQuota.limit(["utilization": 22.0, "resets_at": "2026-11-08T19:00:00.123+00:00"])
        #expect(limit?.used == 0.22)
        #expect(limit?.resetsAt != nil)
        #expect(ClaudeQuota.limit(["used_percentage": 150.0])?.used == 1)
        #expect(ClaudeQuota.limit(["resets_at": "x"]) == nil)
        #expect(ClaudeQuota.limit(nil) == nil)
    }

    @Test func queueReadsUpcomingSectionsFromTheEnd() {
        // Table de Musique, de la fin vers le haut.
        let rows: [[String]] = [
            ["CABBY", "Dominic Fike — HOW TO QUIT SMOKING"],
            ["WHITE KEYS", "Dominic Fike — HOW TO QUIT SMOKING"],
            ["Poursuivre la lecture"],
            ["Ajouté à la main", "Artiste — Album"],
            ["À suivre"],
            ["Déjà écouté", "Quelqu'un — Autre"],
            ["Historique"],
        ]
        let entries = MusicQueueReader.upcoming(fromLastRows: rows)
        #expect(entries.map(\.title) == ["Ajouté à la main", "WHITE KEYS", "CABBY"])
        #expect(entries.first?.artist == "Artiste")
    }

    @Test func emptyQueueWithoutSections() {
        #expect(MusicQueueReader.upcoming(fromLastRows: [["Déjà écouté", "A — B"], ["Historique"]]).isEmpty)
    }

    @Test func nowPlayingPayloads() {
        let now = Date(timeIntervalSince1970: 1_000_010)
        let stamp = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_000_000))
        let info = NowPlayingAdapter.parse([
            "title": "Me at the zoo", "artist": "jawed", "bundleIdentifier": "com.apple.WebKit.GPU",
            "parentApplicationBundleIdentifier": "com.apple.Safari", "playing": true,
            "elapsedTime": 5.0, "duration": 19.0, "timestamp": stamp,
        ], now: now)
        #expect(info?.bundleID == "com.apple.Safari")
        #expect(info?.elapsed == 15)
        #expect(NowPlayingAdapter.parse(["title": ""]) == nil)
    }

    @Test func nowPlayingAcceptsFractionalTimestamps() {
        let info = NowPlayingAdapter.parse([
            "title": "A", "bundleIdentifier": "x", "playing": true, "elapsedTime": 1.0,
            "timestamp": "2026-11-05T08:57:43.500Z",
        ], now: ISO8601DateFormatter().date(from: "2026-11-05T08:57:45Z")!)
        #expect(info?.elapsed == 2.5)
    }

    @Test func clockText() {
        #expect(Clock.text(0) == "0:00")
        #expect(Clock.text(83) == "1:23")
        #expect(Clock.text(-3) == "0:00")
    }

    @MainActor @Test func replyTargets() {
        let working = ClaudeCodeSession(id: "a", cwd: "/p/A", state: .working, detail: nil, updatedAt: .now)
        let other = ClaudeCodeSession(id: "b", cwd: "/p/B", state: .done, detail: nil, updatedAt: .now)
        let all = [working, other]
        func id(_ resolved: ClaudeTabField.Resolved) -> String {
            switch resolved {
            case .session(let session): session.id
            case .newConversation: "new"
            case .quickQuestion: "quick"
            }
        }
        #expect(id(ClaudeTabField.resolve(nil, default: working, among: all)) == "a")
        #expect(id(ClaudeTabField.resolve(nil, default: nil, among: all)) == "new")
        #expect(id(ClaudeTabField.resolve(.session("b"), default: working, among: all)) == "b")
        // Session disparue : retour à la session par défaut.
        #expect(id(ClaudeTabField.resolve(.session("gone"), default: working, among: all)) == "a")
        #expect(id(ClaudeTabField.resolve(.quickQuestion, default: working, among: all)) == "quick")
        #expect(id(ClaudeTabField.resolve(.newConversation, default: working, among: all)) == "new")
    }
}
