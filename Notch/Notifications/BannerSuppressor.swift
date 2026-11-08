import AppKit
import ApplicationServices

/// Ferme les bannières de notification de macOS pendant qu'Encoche tourne : les
/// notifications ne s'affichent alors que dans l'encoche. Quand Encoche est fermée,
/// rien n'est intercepté et macOS affiche ses bannières comme d'habitude.
///
/// Passe par l'Accessibilité : chaque bannière est un élément `AXNotificationCenterBanner`
/// du processus Centre de notifications, avec une action « Fermer ». Les notifications
/// au style « Alertes », qui restent à l'écran (rappels de Calendrier…), sont des
/// `AXNotificationCenterAlert` : elles sont relayées de la même façon. Calendrier ne les
/// enregistre pas dans la base des notifications, l'encoche les reçoit donc par leur contenu.
@MainActor
final class BannerSuppressor {
    private static let bundleID = "com.apple.notificationcenterui"
    private static let bannerSubroles: Set<String> = ["AXNotificationCenterBanner", "AXNotificationCenterAlert"]
    /// Nom de l'action de fermeture selon la langue du système.
    private static let closeActionNames = ["Fermer", "Close", "Schließen", "Cerrar", "Chiudi"]

    /// Appelé juste avant de fermer une bannière, pour lire la notification dans la base
    /// tant qu'elle y est encore (fermer la bannière l'en retire).
    var beforeClosing: (() -> Void)?
    /// Relaie ce qu'affiche une bannière (app, titre, texte ; titre `nil` s'il est illisible)
    /// et dit si elle peut être fermée : `false` tant que son contenu n'est relayé nulle part.
    var relay: (_ app: String, _ title: String?, _ body: String?) -> Bool = { _, _, _ in false }
    /// Faut-il fermer les bannières maintenant ? (relais actif)
    var isEnabled: () -> Bool = { false }
    /// Alertes d'appel affichées (appel de l'iPhone sur le Mac), à chaque passage, même vide :
    /// elles ne sont jamais fermées (ce serait refuser l'appel).
    var onCallAlerts: (([CallAlert]) -> Void)?

    /// Appel entrant affiché par macOS, avec ses boutons (actions d'accessibilité).
    struct CallAlert {
        let element: AXUIElement
        let caller: String
        let detail: String?
        let answerAction: String?
        let declineAction: String?
    }

    /// Libellés des boutons d'appel selon la langue du système.
    private static let answerNames = ["Accepter", "Répondre", "Accept", "Answer"]
    private static let declineNames = ["Refuser", "Decline"]
    /// Apps qui affichent les appels de l'iPhone sur le Mac.
    private static let callApps = ["FaceTime", "Téléphone", "Phone", "iPhone"]

    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var timer: Timer?

    func start() {
        // L'observateur d'accessibilité réagit à chaque bannière ; ce minuteur ne sert qu'à se
        // rattacher si le Centre de notifications redémarre, et de filet de sécurité.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    private func tick() {
        guard AXIsProcessTrusted() else { return }
        attachIfNeeded()
        // Filet de sécurité si une notification d'apparition a été manquée.
        closeBanners()
    }

    private func attachIfNeeded() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first else {
            return
        }
        let pid = app.processIdentifier
        guard pid != observedPID else { return }

        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observedPID = pid

        var newObserver: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let suppressor = Unmanaged<BannerSuppressor>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { suppressor.closeBanners() }
        }
        guard AXObserverCreate(pid, callback, &newObserver) == .success, let newObserver else { return }

        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowCreatedNotification, kAXCreatedNotification, kAXLayoutChangedNotification] {
            AXObserverAddNotification(newObserver, element, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .defaultMode)
        observer = newObserver
    }

    /// Ferme toutes les bannières affichées (pas la liste du Centre de notifications),
    /// sauf les appels, signalés à part.
    func closeBanners() {
        guard observedPID != 0 else { return }
        let app = AXUIElementCreateApplication(observedPID)
        var banners = windows(of: app).flatMap { findBanners(in: $0, depth: 0) }

        let calls = banners.compactMap(callAlert(of:))
        onCallAlerts?(calls)
        banners.removeAll { banner in calls.contains { CFEqual($0.element, banner) } }

        guard isEnabled(), !banners.isEmpty else { return }
        beforeClosing?()
        for banner in banners {
            guard let action = closeAction(of: banner) else { continue }
            let content = content(of: banner)
            guard relay(content.app, content.title, content.body) else { continue }
            AXUIElementPerformAction(banner, action as CFString)
        }
    }

    // MARK: - Accessibilité

    private func windows(of app: AXUIElement) -> [AXUIElement] {
        // Les bannières vivent dans une fenêtre « dialogue système » ; on ignore celles des widgets.
        (attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).filter {
            attribute($0, kAXSubroleAttribute) as? String == kAXSystemDialogSubrole
        }
    }

    private func findBanners(in element: AXUIElement, depth: Int) -> [AXUIElement] {
        if let subrole = attribute(element, kAXSubroleAttribute) as? String, Self.bannerSubroles.contains(subrole) {
            return [element]
        }
        guard depth < 6, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return [] }
        return children.flatMap { findBanners(in: $0, depth: depth + 1) }
    }

    /// App (début de la description, « Mail, … »), titre et texte affichés par la bannière.
    private func content(of banner: AXUIElement) -> (app: String, title: String?, body: String?) {
        let description = attribute(banner, kAXDescriptionAttribute) as? String ?? ""
        let app = description.components(separatedBy: ", ").first ?? ""
        var title: String?
        var body: String?
        for child in attribute(banner, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            let value = attribute(child, kAXValueAttribute) as? String
            switch attribute(child, kAXIdentifierAttribute) as? String {
            case "title": title = value
            case "body": body = value
            default: break
            }
        }
        return (app, title, body)
    }

    /// Alerte d'appel : elle porte un bouton Accepter ou Refuser.
    private func callAlert(of banner: AXUIElement) -> CallAlert? {
        var names: CFArray?
        AXUIElementCopyActionNames(banner, &names)
        let actions = names as? [String] ?? []
        func action(_ labels: [String]) -> String? {
            actions.first { action in labels.contains { action.hasPrefix("Name:\($0)") } }
        }
        let answer = action(Self.answerNames)
        let decline = action(Self.declineNames)
        guard answer != nil || decline != nil else { return nil }
        let content = content(of: banner)
        // Les invitations de Calendrier ont aussi Accepter / Refuser : seuls les appels comptent.
        guard Self.callApps.contains(where: { content.app.localizedCaseInsensitiveContains($0) }) else { return nil }
        return CallAlert(
            element: banner,
            caller: content.title ?? content.body ?? "Appel",
            detail: content.title == nil ? nil : content.body,
            answerAction: answer,
            declineAction: decline
        )
    }

    private func closeAction(of banner: AXUIElement) -> String? {
        var names: CFArray?
        AXUIElementCopyActionNames(banner, &names)
        return (names as? [String])?.first { action in
            Self.closeActionNames.contains { action.hasPrefix("Name:\($0)") }
        }
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return value
    }
}
