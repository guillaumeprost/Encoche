import Foundation

/// Règles « toujours autoriser » de Claude Code, quand il n'en suggère pas lui-même.
///
/// Même format que ses suggestions (`permission_suggestions`) : une mise à jour « addRules »,
/// enregistrée dans les réglages locaux du projet (`.claude/settings.local.json`).
enum ClaudePermissionRules {
    struct Rule: Equatable {
        let toolName: String
        /// `nil` : tout l'outil (Edit, Read…).
        let content: String?
    }

    /// Commandes dont on garde aussi la sous-commande (« git push », « npm test »).
    private static let twoWordCommands: Set<String> = [
        "git", "npm", "npx", "yarn", "pnpm", "bun", "swift", "xcodebuild", "xcrun", "docker", "kubectl", "gh",
        "cargo", "go", "make", "pip", "pip3", "brew", "pod", "bundle", "rails", "php", "composer", "dotnet",
    ]
    /// Jamais autorisées une fois pour toutes.
    private static let neverAlways: Set<String> = ["rm", "sudo", "su", "dd", "mkfs", "chmod", "chown", "kill", "killall"]
    /// Lancent une autre commande : « env:* » ou « bash:* » autoriseraient tout, rm compris.
    private static let launchers: Set<String> = [
        "env", "bash", "sh", "zsh", "fish", "eval", "exec", "xargs", "nohup", "time", "timeout", "nice", "command",
        "builtin", "osascript", "find", "doas",
    ]
    /// Outils qu'on autorise en entier.
    private static let wholeTools: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit", "Read", "Glob", "Grep", "WebSearch"]

    static func rule(tool: String, input: [String: Any]) -> Rule? {
        switch tool {
        case "Bash":
            guard let command = input["command"] as? String, let prefix = commandPrefix(command) else { return nil }
            return Rule(toolName: "Bash", content: "\(prefix):*")
        case "WebFetch":
            guard let url = (input["url"] as? String).flatMap(URL.init(string:)), let host = url.host() else { return nil }
            return Rule(toolName: "WebFetch", content: "domain:\(host)")
        case _ where wholeTools.contains(tool) || tool.hasPrefix("mcp__"):
            return Rule(toolName: tool, content: nil)
        default:
            return nil
        }
    }

    /// « npm test -- --watch » → « npm test » ; « ls -la » → « ls ». `nil` pour une commande
    /// risquée (rm, sudo…) ou illisible.
    static func commandPrefix(_ command: String) -> String? {
        // Seulement la première commande d'un enchaînement (« a && b », « a | b »).
        let first = command.components(separatedBy: CharacterSet(charactersIn: "&|;\n")).first ?? command
        let words = first.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        // Variables d'environnement en tête (« FOO=1 npm test »).
        let command = words.drop { $0.contains("=") && !$0.hasPrefix("-") }
        guard let head = command.first, !head.hasPrefix("-") else { return nil }
        // « /bin/rm » ou « \rm » restent « rm ».
        let name = (head.split(separator: "/").last.map(String.init) ?? head).trimmingCharacters(in: ["\\"])
        guard !neverAlways.contains(name), !launchers.contains(name) else { return nil }
        if twoWordCommands.contains(head), let sub = command.dropFirst().first, !sub.hasPrefix("-") {
            return "\(head) \(sub)"
        }
        return head
    }

    /// Mise à jour de permissions au format de Claude Code.
    static func update(for rule: Rule) -> [String: Any] {
        var entry: [String: Any] = ["toolName": rule.toolName]
        if let content = rule.content { entry["ruleContent"] = content }
        return ["type": "addRules", "rules": [entry], "behavior": "allow", "destination": "localSettings"]
    }

    /// Les règles d'une liste de mises à jour, lisibles : « Bash(npm test:*), WebFetch(domain:x.com) ».
    static func describe(_ updates: [[String: Any]]) -> String? {
        let parts = updates.flatMap { update -> [String] in
            if let mode = update["mode"] as? String { return ["mode \(mode)"] }
            if let directories = update["directories"] as? [String] { return directories.map { "dossier \($0)" } }
            let rules = update["rules"] as? [[String: Any]] ?? []
            return rules.compactMap { rule in
                guard let tool = rule["toolName"] as? String else { return nil }
                return (rule["ruleContent"] as? String).map { "\(tool)(\($0))" } ?? tool
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
