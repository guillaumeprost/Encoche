import Foundation
import Observation

/// Réglages partagés par toutes les encoches, persistés dans les UserDefaults.
@Observable
@MainActor
final class AppSettings {
    /// Liquid Glass pour l'encoche ouverte. Désactivé par défaut : en noir, l'encoche se fond
    /// dans celle du Mac.
    var useGlass: Bool = UserDefaults.standard.object(forKey: "useGlass") as? Bool ?? false {
        didSet { UserDefaults.standard.set(useGlass, forKey: "useGlass") }
    }

    /// Relayer les notifications de macOS dans l'encoche.
    var mirrorSystemNotifications: Bool = UserDefaults.standard.object(forKey: "mirrorSystemNotifications") as? Bool ?? true {
        didSet { UserDefaults.standard.set(mirrorSystemNotifications, forKey: "mirrorSystemNotifications") }
    }

    /// Remplacer l'indicateur de volume de macOS par celui de l'encoche.
    var replaceSystemVolumeHUD: Bool = UserDefaults.standard.object(forKey: "replaceSystemVolumeHUD") as? Bool ?? true {
        didSet { UserDefaults.standard.set(replaceSystemVolumeHUD, forKey: "replaceSystemVolumeHUD") }
    }

    /// Dernier onglet ouvert, retrouvé à la prochaine ouverture.
    var tab: NotchTab = UserDefaults.standard.string(forKey: "tab").flatMap(NotchTab.init) ?? .home {
        didSet { UserDefaults.standard.set(tab.rawValue, forKey: "tab") }
    }

    /// Réglage « Liquid Glass » de macOS (Réglages → Apparence, de Transparent à Teinté),
    /// entre 0 et 1. Le verre SwiftUI d'une fenêtre comme l'encoche ne l'applique pas
    /// de lui-même : on le lit et on teinte le verre en conséquence.
    private(set) var systemGlassTint: Double = AppSettings.readSystemGlassTint()
    private var glassTintObservation: NSKeyValueObservation?

    init() {
        // Suivi en direct quand le curseur bouge dans les Réglages.
        glassTintObservation = UserDefaults.standard.observe(\.NSGlassTintAmount, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.refreshSystemGlassTint() }
        }
    }

    /// Relit le réglage (aussi appelé à chaque ouverture, par sécurité).
    func refreshSystemGlassTint() {
        let value = Self.readSystemGlassTint()
        if value != systemGlassTint { systemGlassTint = value }
    }

    private static func readSystemGlassTint() -> Double {
        // Valeur absente (réglage jamais touché) : position médiane par défaut.
        guard UserDefaults.standard.object(forKey: "NSGlassTintAmount") != nil else { return 0.5 }
        return min(max(UserDefaults.standard.double(forKey: "NSGlassTintAmount"), 0), 1)
    }
}

extension UserDefaults {
    /// Exposé en KVO pour être notifié des changements faits dans les Réglages.
    @objc dynamic var NSGlassTintAmount: Double { double(forKey: "NSGlassTintAmount") }
}
