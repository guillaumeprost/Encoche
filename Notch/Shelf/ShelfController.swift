import AppKit
import Observation

/// Étagère : des fichiers gardés sous la main dans l'encoche (déposés sur l'encoche, ou
/// gardés depuis les captures), à rouvrir, glisser ailleurs ou envoyer par AirDrop.
///
/// On garde des références (pas de copie) : un fichier déplacé ou supprimé
/// disparaît de l'étagère au prochain chargement.
@Observable
@MainActor
final class ShelfController {
    private static let storeKey = "shelfItems"

    private(set) var items: [URL] = []

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.storeKey) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ urls: [URL]) {
        let fresh = urls.filter { url in !items.contains(url) }
        guard !fresh.isEmpty else { return }
        items.insert(contentsOf: fresh, at: 0)
        save()
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        save()
    }

    func removeAll() {
        items.removeAll()
        save()
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Envoie des fichiers par AirDrop (la fenêtre de choix du destinataire s'ouvre).
    func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate()
        service.perform(withItems: urls)
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.path), forKey: Self.storeKey)
    }
}
