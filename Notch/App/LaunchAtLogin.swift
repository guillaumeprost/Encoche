import Foundation
import Observation
import ServiceManagement

/// Ouverture de l'app à l'ouverture de session (Réglages → Général → Ouverture).
///
/// Seule la copie installée dans /Applications s'enregistre : la version de
/// développement (dossier build/) ne doit jamais devenir l'élément d'ouverture.
@Observable
@MainActor
final class LaunchAtLogin {
    private static let configuredKey = "launchAtLoginConfigured"
    /// Choix de l'utilisateur, retenu pour réenregistrer l'app si elle change de nom ou de place.
    private static let wantedKey = "launchAtLoginWanted"

    private(set) var isEnabled = SMAppService.mainApp.status == .enabled

    var isInstalledCopy: Bool {
        Bundle.main.bundleURL.deletingLastPathComponent().path == "/Applications"
    }

    init() {
        // Premier lancement depuis /Applications : activé par défaut.
        let defaults = UserDefaults.standard
        guard isInstalledCopy else { return }
        if !defaults.bool(forKey: Self.configuredKey) {
            defaults.set(true, forKey: Self.configuredKey)
            set(true)
        } else if defaults.object(forKey: Self.wantedKey) as? Bool ?? true {
            // Réenregistre la copie actuelle : l'ancienne inscription peut viser une app
            // renommée ou déplacée (Notch.app → Encoche.app). Sans effet si déjà à jour.
            set(true)
        }
    }

    func set(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.wantedKey)
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("[Encoche] Launch at login change failed: \(error)")
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
