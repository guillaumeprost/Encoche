import Foundation

/// Traduit les appels d'outils de Claude Code en activité lisible
/// (« Modifie HomeView.swift », « Cherche « refresh » »…) et suit son plan.
enum ClaudeActivity {
    /// Outils qui lancent un sous-agent.
    static let agentTools: Set<String> = ["Agent", "Task"]

    static func describe(tool: String, input: [String: Any]) -> String {
        func file(_ key: String = "file_path") -> String {
            (input[key] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? "un fichier"
        }
        func quoted(_ key: String) -> String {
            (input[key] as? String).map { "« \(shorten($0, 60)) »" } ?? ""
        }

        let text: String
        switch tool {
        case "Bash":
            if let description = input["description"] as? String, !description.isEmpty {
                text = description
            } else {
                text = "Lance " + ((input["command"] as? String).map { shorten($0, 80) } ?? "une commande")
            }
        case "Edit", "MultiEdit": text = "Modifie \(file())"
        case "Write": text = "Écrit \(file())"
        case "Read": text = "Lit \(file())"
        case "NotebookEdit": text = "Modifie \(file("notebook_path"))"
        case "Grep": text = "Cherche \(quoted("pattern"))"
        case "Glob": text = "Cherche les fichiers \(quoted("pattern"))"
        case "WebFetch":
            let host = (input["url"] as? String).flatMap { URL(string: $0)?.host() }
            text = "Lit " + (host ?? "une page web")
        case "WebSearch": text = "Recherche \(quoted("query"))"
        case "Agent", "Task":
            text = "Lance un agent : " + ((input["description"] as? String) ?? "tâche")
        case "TodoWrite": text = "Met à jour son plan"
        case "AskUserQuestion": text = "Te pose une question"
        case "Skill": text = "Utilise « \((input["skill"] as? String) ?? "une compétence") »"
        case "ToolSearch": text = "Charge des outils"
        default:
            if tool.hasSuffix("update_plan") {
                text = "Met à jour son plan"
            } else if tool.hasPrefix("mcp__") {
                // mcp__serveur__outil → « outil »
                let name = tool.split(separator: "__").last.map(String.init) ?? tool
                text = "Utilise " + name.replacingOccurrences(of: "_", with: " ")
            } else {
                text = "Utilise \(tool)"
            }
        }
        return text.replacingOccurrences(of: "\n", with: " ")
    }

    /// Met à jour le plan quand Claude écrit sa liste de tâches
    /// (`TodoWrite` dans le terminal, `update_plan` dans l'app Claude).
    static func applyPlan(tool: String, input: [String: Any], to plan: inout [ClaudeCodeSession.PlanItem]) {
        if tool == "TodoWrite", let todos = input["todos"] as? [[String: Any]] {
            plan = items(from: todos)
            return
        }
        guard tool.hasSuffix("update_plan") else { return }

        if let items = input["items"] as? [[String: Any]] {
            plan = self.items(from: items)
            return
        }
        if input["advance"] as? Bool == true {
            if let current = plan.firstIndex(where: { $0.status == .inProgress }) {
                plan[current].status = .completed
            }
            if let next = plan.firstIndex(where: { $0.status == .pending }) {
                plan[next].status = .inProgress
            }
            return
        }
        // Numéros à partir de 1.
        for number in input["done"] as? [Int] ?? [] where plan.indices.contains(number - 1) {
            plan[number - 1].status = .completed
        }
        if let start = input["start"] as? Int, plan.indices.contains(start - 1) {
            for index in plan.indices where plan[index].status == .inProgress { plan[index].status = .pending }
            plan[start - 1].status = .inProgress
        }
    }

    private static func items(from list: [[String: Any]]) -> [ClaudeCodeSession.PlanItem] {
        list.enumerated().compactMap { index, item in
            let status: ClaudeCodeSession.PlanItem.Status
            switch item["status"] as? String {
            case "completed": status = .completed
            case "in_progress": status = .inProgress
            default: status = .pending
            }
            // Pendant l'étape, Claude fournit souvent une forme active (« Écrit les tests »).
            let active = status == .inProgress ? item["activeForm"] as? String : nil
            guard let content = active ?? item["content"] as? String ?? item["subject"] as? String else { return nil }
            return .init(id: index, content: content, status: status)
        }
    }

    private static func shorten(_ text: String, _ limit: Int) -> String {
        let line = text.replacingOccurrences(of: "\n", with: " ")
        return line.count > limit ? String(line.prefix(limit)) + "…" : line
    }
}

/// Lecture de la fin d'une transcription de Claude Code (fichier JSONL).
enum ClaudeTranscript {
    struct Info {
        var title: String?
        var lastPrompt: String?
        var lastMessage: String?
    }

    /// Seule la fin du fichier est lue : les transcriptions peuvent peser des dizaines de Mo.
    private static let tailSize = 768 * 1024

    static func read(path: String) async -> Info {
        await Task.detached(priority: .utility) { parse(path: path) }.value
    }

    private nonisolated static func parse(path: String) -> Info {
        guard let handle = FileHandle(forReadingAtPath: path) else { return Info() }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > UInt64(tailSize) ? size - UInt64(tailSize) : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else { return Info() }

        var info = Info()
        var lines = data.split(separator: UInt8(ascii: "\n"))
        if offset > 0, !lines.isEmpty { lines.removeFirst() } // ligne coupée
        for line in lines.reversed() {
            if info.title != nil && info.lastMessage != nil && info.lastPrompt != nil { break }
            guard let entry = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            switch entry["type"] as? String {
            case "custom-title" where info.title == nil:
                info.title = entry["customTitle"] as? String
            case "last-prompt" where info.lastPrompt == nil:
                info.lastPrompt = entry["lastPrompt"] as? String
            case "summary" where info.title == nil:
                info.title = entry["summary"] as? String
            case "assistant" where info.lastMessage == nil:
                // Les réponses des sous-agents ne sont pas celles de la session.
                guard entry["isSidechain"] as? Bool != true,
                      let message = entry["message"] as? [String: Any],
                      let content = message["content"] as? [[String: Any]] else { continue }
                let text = content
                    .filter { $0["type"] as? String == "text" }
                    .compactMap { $0["text"] as? String }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { info.lastMessage = text }
            default:
                continue
            }
        }
        return info
    }
}
