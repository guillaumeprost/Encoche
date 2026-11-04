import Foundation
import Observation

/// Réglages partagés par toutes les encoches, persistés dans les UserDefaults.
@Observable
@MainActor
final class AppSettings {
    var useGlass: Bool = UserDefaults.standard.object(forKey: "useGlass") as? Bool ?? true {
        didSet { UserDefaults.standard.set(useGlass, forKey: "useGlass") }
    }

    /// Relayer les notifications de macOS dans l'encoche.
    var mirrorSystemNotifications: Bool = UserDefaults.standard.object(forKey: "mirrorSystemNotifications") as? Bool ?? true {
        didSet { UserDefaults.standard.set(mirrorSystemNotifications, forKey: "mirrorSystemNotifications") }
    }

    /// Dernier onglet ouvert, retrouvé à la prochaine ouverture.
    var tab: NotchTab = UserDefaults.standard.string(forKey: "tab").flatMap(NotchTab.init) ?? .home {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: "tab") }
    }
}
