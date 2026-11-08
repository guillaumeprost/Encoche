import Foundation

/// Lecture des données envoyées par les hooks et des transcriptions de Claude Code.
extension ClaudeCodeMonitor {
    /// Question à une seule réponse d'« AskUserQuestion » : son texte et ses choix (4 au plus).
    nonisolated static func singleQuestion(in input: [String: Any]) -> (text: String, options: [String])? {
        guard let questions = input["questions"] as? [[String: Any]], questions.count == 1,
            let question = questions.first, question["multiSelect"] as? Bool != true,
            let text = question["question"] as? String,
            let options = question["options"] as? [[String: Any]]
        else { return nil }
        let labels = Array(options.compactMap { $0["label"] as? String }.prefix(4))
        return labels.isEmpty ? nil : (text, labels)
    }

    /// Paramètres d'« AskUserQuestion » complétés par la réponse choisie (comme dans le SDK).
    nonisolated static func answeredInput(_ input: [String: Any], label: String) -> [String: Any] {
        var input = input
        if let question = (input["questions"] as? [[String: Any]])?.first?["question"] as? String {
            input["answers"] = [question: label]
        }
        return input
    }

    /// Fin de la conversation (256 Ko), où se trouvent les derniers résultats d'outils.
    nonisolated static func transcriptTail(at path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 262_144 ? size - 262_144 : 0)
        return (try? handle.readToEnd()).flatMap { String(decoding: $0, as: UTF8.self) }
    }

    /// Une ligne de la conversation est le résultat (tool_result) de cet appel d'outil.
    nonisolated static func containsResult(in text: String, for toolUseID: String) -> Bool {
        text.split(separator: "\n").contains { line in
            line.contains("\"tool_result\"") && line.contains("\"tool_use_id\":\"\(toolUseID)\"")
        }
    }

    /// Réponse de Claude en texte simple sur une ligne (sans titres, listes ni gras Markdown).
    nonisolated static func plainSummary(_ text: String) -> String {
        let cleaned =
            text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#>-*• ")) }
            .filter { !$0.isEmpty && !$0.hasPrefix("```") }
            .joined(separator: " ")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
        return cleaned.count > 400 ? String(cleaned.prefix(400)) + "…" : cleaned
    }
}
