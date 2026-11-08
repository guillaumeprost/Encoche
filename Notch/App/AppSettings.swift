import Foundation
import Observation

/// Réglages partagés par toutes les encoches, persistés dans les UserDefaults.
@Observable
@MainActor
final class AppSettings {
    /// Apparence de l'encoche ouverte.
    enum NotchStyle: String, CaseIterable, Identifiable {
        /// Noir pur, comme l'encoche du Mac.
        case black
        /// Noir en haut, collé à l'encoche du Mac, qui s'éclaircit en verre vers le bas.
        case darkGlass
        /// Liquid Glass de macOS, qui suit l'apparence claire ou sombre.
        case glass

        var id: String { rawValue }
        var label: String {
            switch self {
            case .black: return "Noir"
            case .darkGlass: return "Verre noir"
            case .glass: return "Liquid Glass"
            }
        }
    }

    var notchStyle: NotchStyle = AppSettings.initialNotchStyle() {
        didSet { UserDefaults.standard.set(notchStyle.rawValue, forKey: "notchStyle") }
    }

    /// L'ancien réglage « Liquid Glass » (oui / non) est repris tel quel.
    private static func initialNotchStyle() -> NotchStyle {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "notchStyle"), let style = NotchStyle(rawValue: raw) { return style }
        return defaults.bool(forKey: "useGlass") ? .glass : .darkGlass
    }

    /// Relayer les notifications de macOS dans l'encoche.
    var mirrorSystemNotifications: Bool = UserDefaults.standard.object(forKey: "mirrorSystemNotifications") as? Bool ?? true {
        didSet { UserDefaults.standard.set(mirrorSystemNotifications, forKey: "mirrorSystemNotifications") }
    }

    /// Masquer les bannières de macOS : les notifications n'apparaissent que dans l'encoche.
    var hideSystemBanners: Bool = UserDefaults.standard.object(forKey: "hideSystemBanners") as? Bool ?? true {
        didSet { UserDefaults.standard.set(hideSystemBanners, forKey: "hideSystemBanners") }
    }

    /// Montrer les notifications seulement sur l'écran principal (celui de la barre de menus,
    /// choisi dans Réglages Système → Moniteurs), comme macOS.
    var notificationsOnPrimaryScreenOnly: Bool = UserDefaults.standard.object(forKey: "notificationsOnPrimaryScreenOnly") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notificationsOnPrimaryScreenOnly, forKey: "notificationsOnPrimaryScreenOnly") }
    }

    /// Remplacer l'indicateur de volume de macOS par celui de l'encoche.
    var replaceSystemVolumeHUD: Bool = UserDefaults.standard.object(forKey: "replaceSystemVolumeHUD") as? Bool ?? true {
        didSet { UserDefaults.standard.set(replaceSystemVolumeHUD, forKey: "replaceSystemVolumeHUD") }
    }

    /// Activités en direct autour de l'encoche repliée.
    var showClaudeActivity: Bool = UserDefaults.standard.object(forKey: "showClaudeActivity") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showClaudeActivity, forKey: "showClaudeActivity") }
    }

    var showDownloadActivity: Bool = UserDefaults.standard.object(forKey: "showDownloadActivity") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showDownloadActivity, forKey: "showDownloadActivity") }
    }

    var showMeetingActivity: Bool = UserDefaults.standard.object(forKey: "showMeetingActivity") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showMeetingActivity, forKey: "showMeetingActivity") }
    }

    var showFocusActivity: Bool = UserDefaults.standard.object(forKey: "showFocusActivity") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showFocusActivity, forKey: "showFocusActivity") }
    }

    var showBluetoothActivity: Bool = UserDefaults.standard.object(forKey: "showBluetoothActivity") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showBluetoothActivity, forKey: "showBluetoothActivity") }
    }

    /// Écran de verrouillage : cadenas dans l'encoche et lecteur de musique.
    var showOnLockScreen: Bool = UserDefaults.standard.object(forKey: "showOnLockScreen") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showOnLockScreen, forKey: "showOnLockScreen") }
    }

    var lockScreenMusic: Bool = UserDefaults.standard.object(forKey: "lockScreenMusic") as? Bool ?? true {
        didSet { UserDefaults.standard.set(lockScreenMusic, forKey: "lockScreenMusic") }
    }

    var lockScreenActivities: Bool = UserDefaults.standard.object(forKey: "lockScreenActivities") as? Bool ?? true {
        didSet { UserDefaults.standard.set(lockScreenActivities, forKey: "lockScreenActivities") }
    }

    var lockSound: LockSound = UserDefaults.standard.string(forKey: "lockSound").flatMap(LockSound.init) ?? .none {
        didSet { UserDefaults.standard.set(lockSound.rawValue, forKey: "lockSound") }
    }

    var unlockSound: LockSound = UserDefaults.standard.string(forKey: "unlockSound").flatMap(LockSound.init) ?? .none {
        didSet { UserDefaults.standard.set(unlockSound.rawValue, forKey: "unlockSound") }
    }

    /// Ouvre la fenêtre de réglages (branché par l'app au lancement).
    @ObservationIgnored var openSettings: () -> Void = {}

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
    /// Le nom doit être celui de la clé de macOS.
    // swift-format-ignore: AlwaysUseLowerCamelCase
    @objc dynamic var NSGlassTintAmount: Double { double(forKey: "NSGlassTintAmount") }
}
