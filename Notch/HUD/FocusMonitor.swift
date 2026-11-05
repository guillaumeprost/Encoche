import Foundation
import Observation

/// Mode Concentration de macOS (Ne pas déranger, Travail, Repos…).
///
/// Pas d'API publique : on lit les fichiers où macOS enregistre le mode actif
/// (`~/Library/DoNotDisturb/DB`), lisibles grâce à l'accès complet au disque.
/// Un mode programmé par horaire peut ne pas y figurer tant qu'il n'est pas déclenché.
@Observable
@MainActor
final class FocusMonitor {
    struct Mode: Equatable {
        let name: String
        let symbol: String
    }

    private(set) var activeMode: Mode?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastModified: Date?

    private static let folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB")

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func refresh() {
        let assertions = Self.folder.appendingPathComponent("Assertions.json")
        let modified = (try? assertions.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard modified != lastModified else { return }
        lastModified = modified
        let mode = Self.readActiveMode()
        if mode != activeMode { activeMode = mode }
    }

    private static func readActiveMode() -> Mode? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("Assertions.json")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let store = (root["data"] as? [[String: Any]])?.first,
              let records = store["storeAssertionRecords"] as? [[String: Any]], !records.isEmpty
        else { return nil }
        let identifier = (records.last?["assertionDetails"] as? [String: Any])?["assertionDetailsModeIdentifier"] as? String
        return mode(for: identifier) ?? Mode(name: "Concentration", symbol: "moon.fill")
    }

    /// Nom et symbole du mode, d'après les réglages de Concentration.
    private static func mode(for identifier: String?) -> Mode? {
        guard let identifier,
              let data = try? Data(contentsOf: folder.appendingPathComponent("ModeConfigurations.json")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let configurations = ((root["data"] as? [[String: Any]])?.first?["modeConfigurations"]) as? [String: Any],
              let mode = ((configurations[identifier] as? [String: Any])?["mode"]) as? [String: Any]
        else { return nil }
        let name = mode["name"] as? String ?? "Concentration"
        return Mode(
            name: name == "Do Not Disturb" ? "Ne pas déranger" : name,
            symbol: mode["symbolImageName"] as? String ?? "moon.fill"
        )
    }
}
