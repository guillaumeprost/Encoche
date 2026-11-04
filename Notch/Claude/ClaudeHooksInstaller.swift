import Foundation

/// Ajoute (ou retire) dans `~/.claude/settings.json` les hooks qui envoient
/// les événements de Claude Code à l'encoche.
///
/// - Les hooks existants ne sont jamais modifiés : on ajoute nos propres entrées,
///   reconnaissables à leur URL, et on ne retire que celles-là.
/// - Une copie de sauvegarde est faite avant chaque écriture.
/// - La commande échoue en silence (timeout 1 s) si l'app n'est pas lancée :
///   Claude Code n'est jamais bloqué.
enum ClaudeHooksInstaller {
    enum InstallError: LocalizedError {
        case unreadableSettings

        var errorDescription: String? {
            "~/.claude/settings.json n'est pas un JSON valide : corrige-le avant d'installer les hooks."
        }
    }

    static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "Notification", "Stop", "SessionEnd"]
    static let marker = "127.0.0.1:\(HookServer.port)\(HookServer.path)"
    static let command =
        "curl -s -m 1 -X POST -H 'Content-Type: application/json' --data-binary @- http://\(marker) >/dev/null 2>&1 || true"

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    static var isInstalled: Bool {
        guard let data = try? Data(contentsOf: settingsURL) else { return false }
        return String(decoding: data, as: UTF8.self).contains(marker)
    }

    static func install() throws {
        var root = try readSettings()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            guard !groups.contains(where: isOurs) else { continue }
            var group: [String: Any] = ["hooks": [["type": "command", "command": command]]]
            if event == "PreToolUse" { group["matcher"] = "*" }
            groups.append(group)
            hooks[event] = groups
        }
        root["hooks"] = hooks
        try writeSettings(root)
    }

    static func uninstall() throws {
        var root = try readSettings()
        guard var hooks = root["hooks"] as? [String: Any] else { return }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept = groups.filter { !isOurs($0) }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        try writeSettings(root)
    }

    private static func isOurs(_ group: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: group, options: .withoutEscapingSlashes) else {
            return false
        }
        return String(decoding: data, as: UTF8.self).contains(marker)
    }

    private static func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallError.unreadableSettings
        }
        return root
    }

    private static func writeSettings(_ root: [String: Any]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: settingsURL.path) {
            let backup = settingsURL.appendingPathExtension("notch-backup")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: settingsURL, to: backup)
        }
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: settingsURL, options: .atomic)
    }
}
