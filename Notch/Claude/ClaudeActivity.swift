import Foundation

/// Traduit les appels d'outils de Claude Code en activité lisible
/// (« Modifie HomeView.swift », « Cherche « refresh » »…) et suit son plan.
enum ClaudeActivity {
    /// Outils qui lancent un sous-agent.
    static let agentTools: Set<String> = ["Agent", "Task"]
    /// Activité affichée pendant que Claude Code résume la conversation pour libérer du contexte.
    static let compacting = "Compacte la conversation"

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

    /// Résumé court de ce qu'un outil s'apprête à faire, pour une demande de permission
    /// (la commande, le fichier, l'adresse…).
    static func summarize(tool: String, input: [String: Any]) -> String {
        let value: String?
        switch tool {
        case "Bash":
            value = input["command"] as? String
        case "Edit", "MultiEdit", "Write", "Read", "NotebookEdit":
            let file = (input["file_path"] as? String ?? input["notebook_path"] as? String)
                .map { URL(fileURLWithPath: $0).lastPathComponent }
            value = [file, diffStat(tool: tool, input: input)].compactMap { $0 }.joined(separator: " · ")
        case "WebFetch":
            value = input["url"] as? String
        case "WebSearch":
            value = input["query"] as? String
        default:
            value = input["description"] as? String
        }
        return shorten(value ?? tool, 140)
    }

    /// Ligne d'un aperçu de modification : retirée, ajoutée, ou « … » pour les lignes masquées.
    struct DiffLine: Equatable, Identifiable {
        enum Kind: Equatable { case removed, added, more }
        let id: Int
        let kind: Kind
        let text: String
    }

    /// Ce que va changer `Edit`, `MultiEdit` ou `Write` : lignes retirées puis ajoutées, sans les
    /// lignes identiques au début et à la fin. `nil` pour les autres outils.
    static func diff(tool: String, input: [String: Any], limit: Int = 12) -> [DiffLine]? {
        var raw: [(DiffLine.Kind, String)] = []
        switch tool {
        case "Edit":
            raw = changedLines(old: input["old_string"] as? String ?? "", new: input["new_string"] as? String ?? "")
        case "MultiEdit":
            for edit in input["edits"] as? [[String: Any]] ?? [] {
                raw += changedLines(old: edit["old_string"] as? String ?? "", new: edit["new_string"] as? String ?? "")
            }
        case "Write":
            raw = lines(input["content"] as? String ?? "").map { (.added, $0) }
        default:
            return nil
        }
        guard !raw.isEmpty else { return nil }
        var result = raw.prefix(limit).enumerated().map { DiffLine(id: $0, kind: $1.0, text: $1.1) }
        if raw.count > limit {
            result.append(DiffLine(id: limit, kind: .more, text: "\(raw.count - limit) lignes de plus"))
        }
        return result
    }

    /// Outils qui modifient un fichier.
    static let editTools: Set<String> = ["Edit", "MultiEdit", "Write", "NotebookEdit"]

    /// Lignes ajoutées et retirées par une modification.
    static func lineCounts(tool: String, input: [String: Any]) -> (added: Int, removed: Int) {
        guard let lines = diff(tool: tool, input: input, limit: .max) else { return (0, 0) }
        return (lines.filter { $0.kind == .added }.count, lines.filter { $0.kind == .removed }.count)
    }

    /// Commande qui lance des tests (npm test, pytest, xcodebuild test, ./scripts/test.sh…).
    static func isTestCommand(_ command: String) -> Bool {
        let text = command.lowercased()
        let patterns = [
            "npm test", "npm run test", "yarn test", "pnpm test", "bun test", "pytest", "jest", "vitest",
            "xcodebuild test", "xcodebuild -", "swift test", "cargo test", "go test", "rspec", "phpunit",
            "mvn test", "gradle test", "./gradlew test", "test.sh", "make test", "rake test", "mix test",
        ]
        return patterns.contains { pattern in
            // « xcodebuild - » ne compte que s'il lance bien des tests.
            pattern == "xcodebuild -" ? text.contains("xcodebuild") && text.hasSuffix(" test") : text.contains(pattern)
        }
    }

    /// Le résultat d'un outil (PostToolUse) signale une erreur.
    static func didFail(_ response: Any?) -> Bool {
        if let text = response as? String {
            return text.hasPrefix("Error") || text.contains("<tool_use_error>") || failedExitCode(in: text)
        }
        guard let response = response as? [String: Any] else { return false }
        if response["is_error"] as? Bool == true || response["isError"] as? Bool == true { return true }
        if let error = response["error"] as? String, !error.isEmpty { return true }
        if let code = (response["exitCode"] ?? response["exit_code"]) as? Int, code != 0 { return true }
        return [response["stdout"], response["stderr"], response["output"]].contains { ($0 as? String).map(failedExitCode) ?? false }
    }

    /// « Exit code 1 » écrit par Claude Code quand une commande échoue.
    private static func failedExitCode(in text: String) -> Bool {
        guard let match = text.firstMatch(of: /Exit code (\d+)/), let code = Int(match.1) else { return false }
        return code != 0
    }

    /// Nombre de lignes retirées et ajoutées (« +3 −1 »), pour le résumé d'une demande.
    static func diffStat(tool: String, input: [String: Any]) -> String? {
        guard let lines = diff(tool: tool, input: input, limit: .max) else { return nil }
        let added = lines.filter { $0.kind == .added }.count
        let removed = lines.filter { $0.kind == .removed }.count
        return removed > 0 ? "+\(added) −\(removed)" : "+\(added)"
    }

    private static func changedLines(old: String, new: String) -> [(DiffLine.Kind, String)] {
        var before = lines(old)[...]
        var after = lines(new)[...]
        while let a = before.first, let b = after.first, a == b {
            before.removeFirst()
            after.removeFirst()
        }
        while let a = before.last, let b = after.last, a == b {
            before.removeLast()
            after.removeLast()
        }
        return before.map { (.removed, $0) } + after.map { (.added, $0) }
    }

    private static func lines(_ text: String) -> [String] {
        text.isEmpty ? [] : text.components(separatedBy: "\n")
    }

    /// Réponses proposées à la fin d'une réponse : la question et les boutons de réponse
    /// (`wrap_up` dans l'app Claude). Les boutons d'action de l'app (commit…) sont ignorés.
    static func suggestedReplies(tool: String, input: [String: Any]) -> ClaudeCodeSession.Choices? {
        guard tool.hasSuffix("wrap_up"), let question = input["ask"] as? String, !question.isEmpty else { return nil }
        let actions: [[String: Any]]
        if let list = input["actions"] as? [[String: Any]] {
            actions = list
        } else if let text = input["actions"] as? String, let data = text.data(using: .utf8),
            let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        {
            actions = list
        } else {
            return nil
        }
        let labels = actions.filter { $0["action"] == nil }.compactMap { $0["label"] as? String }
        return labels.isEmpty ? nil : .init(question: question, options: labels)
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
    struct Info: Sendable {
        var title: String?
        var cwd: String?
        var lastPrompt: String?
        var lastMessage: String?
    }

    /// Seule la fin du fichier est lue : les transcriptions peuvent peser des dizaines de Mo.
    private static let tailSize = 768 * 1024

    static func read(path: String) async -> Info {
        await Task.detached(priority: .utility) { parse(path: path) }.value
    }

    struct Recent: Sendable {
        let id: String
        let path: String
        let date: Date
        let info: Info
    }

    /// Dernières sessions d'après les transcriptions (`~/.claude/projects/<projet>/<session>.jsonl`).
    static func recentSessions(limit: Int) async -> [Recent] {
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
            let keys: [URLResourceKey] = [.contentModificationDateKey]
            let folders = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            var files: [(URL, Date)] = []
            for folder in folders {
                for file in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
                where file.pathExtension == "jsonl" {
                    let date = (try? file.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
                    files.append((file, date))
                }
            }
            return files.sorted { $0.1 > $1.1 }.prefix(limit).map { file, date in
                Recent(
                    id: file.deletingPathExtension().lastPathComponent, path: file.path, date: date,
                    info: parse(path: file.path))
            }
        }.value
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
            if info.title != nil && info.lastMessage != nil && info.lastPrompt != nil && info.cwd != nil { break }
            guard let entry = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if info.cwd == nil, let cwd = entry["cwd"] as? String { info.cwd = cwd }
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
                    let content = message["content"] as? [[String: Any]]
                else { continue }
                let text =
                    content
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
