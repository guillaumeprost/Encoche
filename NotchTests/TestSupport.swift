import Foundation
import Network

@testable import Encoche

/// Dossier temporaire propre à chaque test, supprimé à la fin.
final class TemporaryFolder {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("encoche-test-\(UUID().uuidString)")

    func file(_ name: String) -> URL { url.appendingPathComponent(name) }

    deinit { try? FileManager.default.removeItem(at: url) }
}

/// Réponse à une demande de permission sur une connexion jamais ouverte : rien n'est envoyé.
@MainActor
func testReply() -> HookReply {
    HookReply(connection: NWConnection(host: "127.0.0.1", port: 9, using: .tcp))
}
