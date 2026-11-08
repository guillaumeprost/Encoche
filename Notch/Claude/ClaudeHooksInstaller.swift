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

    static let events = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Notification", "Stop", "SessionEnd",
    ]
    /// Les événements d'outils (`PreToolUse`…) exigent un matcher.
    private static let toolEvents: Set<String> = ["PreToolUse", "PostToolUse", "PermissionRequest"]

    static let marker = "127.0.0.1:\(HookServer.port)\(HookServer.path)"
    /// `$PPID` = processus Claude Code qui lance le hook : Encoche remonte jusqu'à son app.
    private static let pidHeader = "-H \"\(HookServer.pidHeader): $PPID\""

    static let command =
        "curl -s -m 1 -X POST -H 'Content-Type: application/json' \(pidHeader) --data-binary @- http://\(marker) >/dev/null 2>&1 || true"

    /// Demande de permission : on attend ta réponse dans l'encoche (5 min max) et on renvoie
    /// la décision sur stdout. Sans réponse, ou si l'app n'est pas lancée, rien n'est écrit :
    /// Claude Code garde son fonctionnement habituel.
    static let permissionTimeout = 300
    static let permissionCommand =
        "curl -s -m \(permissionTimeout - 10) -X POST -H 'Content-Type: application/json' \(pidHeader) --data-binary @- "
        + "http://127.0.0.1:\(HookServer.port)\(HookServer.permissionPath) 2>/dev/null || true"

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    static var isInstalled: Bool { isInstalled(at: settingsURL) }

    static func isInstalled(at settingsURL: URL) -> Bool {
        guard let data = try? Data(contentsOf: settingsURL) else { return false }
        return String(decoding: data, as: UTF8.self).contains(marker)
    }

    /// Ajoute les hooks manquants (idempotent : n'écrit rien si tout est déjà là).
    static func install(at settingsURL: URL = settingsURL) throws {
        var root = try readSettings(at: settingsURL)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var changed = false
        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            let expected = event == "PermissionRequest" ? permissionCommand : command
            // Déjà à jour ? Sinon on remplace notre ancienne version (les autres hooks ne bougent pas).
            if groups.contains(where: { isOurs($0) && commandOf($0) == expected }) { continue }
            groups.removeAll(where: isOurs)
            var handler: [String: Any] = ["type": "command", "command": command]
            if event == "PermissionRequest" {
                handler = ["type": "command", "command": permissionCommand, "timeout": permissionTimeout]
            }
            var group: [String: Any] = ["hooks": [handler]]
            if toolEvents.contains(event) { group["matcher"] = "*" }
            groups.append(group)
            hooks[event] = groups
            changed = true
        }
        guard changed else { return }
        root["hooks"] = hooks
        try writeSettings(root, to: settingsURL)
    }

    static func uninstall(at settingsURL: URL = settingsURL) throws {
        var root = try readSettings(at: settingsURL)
        guard var hooks = root["hooks"] as? [String: Any] else { return }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept = groups.filter { !isOurs($0) }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        try writeSettings(root, to: settingsURL)
    }

    private static func commandOf(_ group: [String: Any]) -> String? {
        (group["hooks"] as? [[String: Any]])?.first?["command"] as? String
    }

    private static func isOurs(_ group: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: group, options: .withoutEscapingSlashes) else {
            return false
        }
        return String(decoding: data, as: UTF8.self).contains(marker)
    }

    private static func readSettings(at settingsURL: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw InstallError.unreadableSettings
        }
        return root
    }

    private static func writeSettings(_ root: [String: Any], to settingsURL: URL) throws {
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
