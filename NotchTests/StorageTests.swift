import Foundation
import Testing

@testable import Encoche

/// Dossier temporaire propre à chaque test, supprimé à la fin.
private final class TemporaryFolder {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("encoche-test-\(UUID().uuidString)")

    func file(_ name: String) -> URL { url.appendingPathComponent(name) }

    deinit { try? FileManager.default.removeItem(at: url) }
}

/// Installation des hooks dans un `settings.json` de test (jamais le vrai `~/.claude`).
struct ClaudeHooksInstallerTests {
    private let folder = TemporaryFolder()
    private var settings: URL { folder.file(".claude/settings.json") }

    private func write(_ json: String) throws {
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try json.write(to: settings, atomically: true, encoding: .utf8)
    }

    private func read() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
    }

    private func groups(_ event: String, in root: [String: Any]) -> [[String: Any]] {
        (root["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
    }

    private func commands(_ group: [String: Any]) -> [String] {
        (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
    }

    @Test func createsTheFileWithEveryEvent() throws {
        #expect(!ClaudeHooksInstaller.isInstalled(at: settings))
        try ClaudeHooksInstaller.install(at: settings)
        #expect(ClaudeHooksInstaller.isInstalled(at: settings))

        let root = try read()
        for event in ClaudeHooksInstaller.events {
            #expect(groups(event, in: root).count == 1, "\(event)")
        }
        // Les événements d'outils ont un matcher, les autres non.
        #expect(groups("PreToolUse", in: root).first?["matcher"] as? String == "*")
        #expect(groups("Stop", in: root).first?["matcher"] == nil)
        #expect(commands(groups("Stop", in: root)[0]) == [ClaudeHooksInstaller.command])
    }

    @Test func permissionHookWaitsForTheAnswer() throws {
        try ClaudeHooksInstaller.install(at: settings)
        let handler = try #require((groups("PermissionRequest", in: try read()).first?["hooks"] as? [[String: Any]])?.first)
        #expect(handler["command"] as? String == ClaudeHooksInstaller.permissionCommand)
        #expect(handler["timeout"] as? Int == ClaudeHooksInstaller.permissionTimeout)
    }

    @Test func keepsYourSettingsAndHooks() throws {
        try write(
            """
            {"model": "opus", "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "say fini"}]}]}}
            """)
        try ClaudeHooksInstaller.install(at: settings)
        let root = try read()
        #expect(root["model"] as? String == "opus")
        let stop = groups("Stop", in: root).flatMap(commands)
        #expect(stop == ["say fini", ClaudeHooksInstaller.command])
    }

    @Test func installingTwiceChangesNothing() throws {
        try ClaudeHooksInstaller.install(at: settings)
        let first = try Data(contentsOf: settings)
        try ClaudeHooksInstaller.install(at: settings)
        #expect(try Data(contentsOf: settings) == first)
        #expect(groups("Stop", in: try read()).count == 1)
    }

    @Test func replacesAnOlderVersionOfOurHook() throws {
        let old = "curl -s http://\(ClaudeHooksInstaller.marker) || true"
        try write(
            """
            {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "\(old)"}]}]}}
            """)
        try ClaudeHooksInstaller.install(at: settings)
        #expect(groups("Stop", in: try read()).flatMap(commands) == [ClaudeHooksInstaller.command])
    }

    @Test func backsUpBeforeWriting() throws {
        try write(#"{"model": "opus"}"#)
        try ClaudeHooksInstaller.install(at: settings)
        let backup = settings.appendingPathExtension("notch-backup")
        #expect(try String(contentsOf: backup, encoding: .utf8) == #"{"model": "opus"}"#)
    }

    @Test func uninstallRemovesOnlyOurHooks() throws {
        try write(
            """
            {"model": "opus", "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "say fini"}]}]}}
            """)
        try ClaudeHooksInstaller.install(at: settings)
        try ClaudeHooksInstaller.uninstall(at: settings)
        #expect(!ClaudeHooksInstaller.isInstalled(at: settings))

        let root = try read()
        #expect(root["model"] as? String == "opus")
        let hooks = try #require(root["hooks"] as? [String: Any])
        #expect(Array(hooks.keys) == ["Stop"])
        #expect(groups("Stop", in: root).flatMap(commands) == ["say fini"])
    }

    @Test func uninstallDropsTheEmptyHooksSection() throws {
        try ClaudeHooksInstaller.install(at: settings)
        try ClaudeHooksInstaller.uninstall(at: settings)
        #expect(try read()["hooks"] == nil)
    }

    @Test func invalidSettingsAreLeftUntouched() throws {
        try write("{ pas du json")
        #expect(throws: ClaudeHooksInstaller.InstallError.self) {
            try ClaudeHooksInstaller.install(at: settings)
        }
        #expect(try String(contentsOf: settings, encoding: .utf8) == "{ pas du json")
    }
}

/// Historique des notifications enregistré sur le disque.
@MainActor
struct NotificationHistoryTests {
    private let folder = TemporaryFolder()
    private var file: URL { folder.file("notifications.json") }

    init() throws {
        try FileManager.default.createDirectory(at: folder.url, withIntermediateDirectories: true)
    }

    @Test func historySurvivesARestart() throws {
        let center = AlertCenter(historyURL: file)
        center.post(
            NotchAlert(
                icon: .app(bundleID: "com.apple.mail"), source: "Mail", title: "Nouveau message", body: "Salut",
                action: .openApp(bundleID: "com.apple.mail")))
        center.post(
            NotchAlert(
                icon: .symbol("checkmark", .green), source: "Encoche", title: "Lien", body: nil,
                action: .openURL(URL(string: "https://example.com")!)))

        let restored = AlertCenter(historyURL: file).history
        #expect(restored.map(\.title) == ["Lien", "Nouveau message"])
        #expect(restored.map(\.id) == center.history.map(\.id))
        #expect(restored.last?.body == "Salut")
        if case .openURL(let url) = restored.first?.action {
            #expect(url.absoluteString == "https://example.com")
        } else {
            Issue.record("L'ouverture du lien est perdue")
        }
        if case .symbol(let name, let color) = restored.first?.icon {
            #expect(name == "checkmark")
            #expect(color == .green)
        } else {
            Issue.record("L'icône est perdue")
        }
        if case .openApp(let bundleID) = restored.last?.action {
            #expect(bundleID == "com.apple.mail")
        } else {
            Issue.record("L'ouverture de l'app est perdue")
        }
    }

    @Test func internalActionsAreNotRestored() {
        let center = AlertCenter(historyURL: file)
        center.post(NotchAlert(icon: .symbol("bell.fill", .gray), source: "Claude", title: "Terminé", body: nil, action: .run {}))
        #expect(AlertCenter(historyURL: file).history.first?.action == nil)
    }

    @Test func clearingTheHistoryIsSaved() {
        let center = AlertCenter(historyURL: file)
        center.post(NotchAlert(icon: .symbol("bell.fill", .gray), source: "Test", title: "A", body: nil))
        center.clearHistory()
        #expect(AlertCenter(historyURL: file).history.isEmpty)
    }

    @Test func unreadableFileGivesAnEmptyHistory() throws {
        try "pas du json".write(to: file, atomically: true, encoding: .utf8)
        #expect(AlertCenter(historyURL: file).history.isEmpty)
    }
}
