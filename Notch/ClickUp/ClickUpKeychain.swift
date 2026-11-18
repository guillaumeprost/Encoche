import Foundation
import Security

/// Le jeton ClickUp, dans le Trousseau de session.
///
/// Lu et écrit avec l'outil `security`, comme la connexion de Claude Code. Créé par l'app
/// elle-même, l'élément n'était autorisé que pour une compilation précise d'Encoche (sans
/// identifiant d'équipe, macOS retient son empreinte) : le Trousseau redemandait l'accès après
/// chaque mise à jour. L'outil `security`, lui, reste le même.
enum ClickUpKeychain {
    nonisolated static let service = "com.guillaumeprost.notch.clickup-token"
    nonisolated static let account = "api-token"
    /// Élément des versions 1.2.0 et avant, écrit par l'app.
    private nonisolated static let legacyService = "com.guillaumeprost.notch.clickup"
    private nonisolated static let tool = "/usr/bin/security"

    /// Le jeton enregistré, `nil` s'il n'y en a pas.
    nonisolated static func read() async -> String? {
        if let output = await ProcessRunner.run(tool, ["find-generic-password", "-s", service, "-a", account, "-w"]),
            output.status == 0
        {
            let token = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return token.isEmpty ? nil : token
        }
        // Ancien élément : lu une dernière fois (le Trousseau peut encore demander), puis déplacé.
        guard let legacy = await Task.detached(operation: { readLegacy() }).value else { return nil }
        if await save(legacy) { deleteLegacy() }
        return legacy
    }

    /// Enregistre le jeton (remplace l'ancien). `false` si l'outil a échoué.
    @discardableResult
    nonisolated static func save(_ token: String) async -> Bool {
        guard let command = addCommand(token) else { return false }
        // Le jeton passe par l'entrée standard (mode interactif) : pas dans les arguments.
        let output = await ProcessRunner.run(tool, ["-i"], input: Data(command.utf8))
        return output?.status == 0
    }

    nonisolated static func delete() async {
        _ = await ProcessRunner.run(tool, ["delete-generic-password", "-s", service, "-a", account])
        deleteLegacy()
    }

    /// Commande `security -i` qui enregistre le jeton, `nil` pour un jeton vide ou sur
    /// plusieurs lignes.
    nonisolated static func addCommand(_ token: String) -> String? {
        guard !token.isEmpty, !token.contains(where: \.isNewline) else { return nil }
        func quoted(_ text: String) -> String {
            "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        return "add-generic-password -U -s \(quoted(service)) -a \(quoted(account)) -w \(quoted(token))\n"
    }

    // MARK: - Ancien élément

    private nonisolated static var legacyQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: account,
        ]
    }

    private nonisolated static func readLegacy() -> String? {
        var query = legacyQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private nonisolated static func deleteLegacy() {
        SecItemDelete(legacyQuery as CFDictionary)
    }
}
