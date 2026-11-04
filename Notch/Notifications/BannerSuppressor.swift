import AppKit
import ApplicationServices

/// Ferme les bannières de notification de macOS pendant que Notch tourne : les
/// notifications ne s'affichent alors que dans l'encoche. Quand Notch est fermée,
/// rien n'est intercepté et macOS affiche ses bannières comme d'habitude.
///
/// Passe par l'Accessibilité : chaque bannière est un élément `AXNotificationCenterBanner`
/// du processus Centre de notifications, avec une action « Fermer ».
@MainActor
final class BannerSuppressor {
    private static let bundleID = "com.apple.notificationcenterui"
    private static let bannerSubrole = "AXNotificationCenterBanner"
    /// Nom de l'action de fermeture selon la langue du système.
    private static let closeActionNames = ["Fermer", "Close", "Schließen", "Cerrar", "Chiudi"]

    /// Appelé juste avant de fermer une bannière, pour lire la notification dans la base
    /// tant qu'elle y est encore (fermer la bannière l'en retire).
    var beforeClosing: (() -> Void)?
    /// Filet de sécurité : la bannière est fermée avant que la notification n'ait été lue
    /// dans la base. On transmet ce qu'elle affiche (app, titre, texte).
    var onUnreadBanner: ((_ app: String, _ title: String, _ body: String?) -> Void)?
    /// Faut-il fermer les bannières maintenant ? (relais actif et accès accordé)
    var isEnabled: () -> Bool = { false }

    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var timer: Timer?

    func start() {
        // Le Centre de notifications peut redémarrer : on surveille et on se rattache.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
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

    /// Ferme toutes les bannières affichées (pas la liste du Centre de notifications).
    func closeBanners() {
        guard isEnabled(), observedPID != 0 else { return }
        let app = AXUIElementCreateApplication(observedPID)
        let banners = windows(of: app).flatMap { findBanners(in: $0, depth: 0) }
        guard !banners.isEmpty else { return }

        beforeClosing?()
        for banner in banners {
            guard let action = closeAction(of: banner) else { continue }
            let content = content(of: banner)
            if let title = content.title { onUnreadBanner?(content.app, title, content.body) }
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
        if attribute(element, kAXSubroleAttribute) as? String == Self.bannerSubrole { return [element] }
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
