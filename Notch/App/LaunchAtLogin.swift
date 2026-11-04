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

    private(set) var isEnabled = SMAppService.mainApp.status == .enabled

    var isInstalledCopy: Bool {
        Bundle.main.bundleURL.deletingLastPathComponent().path == "/Applications"
    }

    init() {
        // Premier lancement depuis /Applications : activé par défaut.
        if isInstalledCopy, !UserDefaults.standard.bool(forKey: Self.configuredKey) {
            UserDefaults.standard.set(true, forKey: Self.configuredKey)
            set(true)
        }
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("[Notch] Launch at login change failed: \(error)")
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
