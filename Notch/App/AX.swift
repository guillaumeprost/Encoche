import ApplicationServices

/// Outils d'Accessibilité partagés : lire et parcourir les éléments d'interface des autres apps
/// (Centre de notifications, Musique, Safari, app Claude).
enum AX {
    nonisolated static func string(_ element: AXUIElement, _ name: String) -> String? {
        value(element, name) as? String
    }

    /// Élément d'un attribut (fenêtre au premier plan, parent…), vérifié avant conversion.
    nonisolated static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = value(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    /// Liste d'éléments d'un attribut (enfants, fenêtres, lignes d'une table…).
    nonisolated static func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        value(element, name) as? [AXUIElement] ?? []
    }

    nonisolated static func children(_ element: AXUIElement) -> [AXUIElement] {
        elements(element, kAXChildrenAttribute)
    }

    nonisolated static func role(_ element: AXUIElement) -> String? {
        string(element, kAXRoleAttribute)
    }

    /// Nom affiché : le titre, ou la description quand le titre est vide (fréquent dans les apps web).
    nonisolated static func label(of element: AXUIElement) -> String {
        if let title = string(element, kAXTitleAttribute), !title.isEmpty { return title }
        return string(element, kAXDescriptionAttribute) ?? ""
    }

    /// App par son processus. `manual` : demande à une app Electron (app Claude) d'exposer son
    /// contenu, qu'elle ne publie sinon que pour les lecteurs d'écran.
    nonisolated static func app(_ pid: pid_t, manual: Bool = false) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        if manual { AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue) }
        return app
    }

    /// Fenêtre principale d'une app (sinon celle qui a le focus).
    nonisolated static func mainWindow(of app: AXUIElement) -> AXUIElement? {
        elements(app, kAXWindowsAttribute).first ?? element(app, kAXFocusedWindowAttribute)
    }

    /// Premier élément (parcours en profondeur) qui correspond. `skipping` : rôles dans lesquels
    /// on ne descend pas (listes de centaines de lignes…).
    nonisolated static func first(in element: AXUIElement, maxDepth: Int = 60, skipping: Set<String> = [],
                                  where match: (AXUIElement) -> Bool) -> AXUIElement? {
        func search(_ node: AXUIElement, _ depth: Int) -> AXUIElement? {
            if match(node) { return node }
            guard depth < maxDepth, depth == 0 || !skipping.contains(role(node) ?? "") else { return nil }
            for child in children(node) {
                if let found = search(child, depth + 1) { return found }
            }
            return nil
        }
        return search(element, 0)
    }

    /// Tous les éléments qui correspondent, dans l'ordre du parcours.
    nonisolated static func collect(in element: AXUIElement, maxDepth: Int = 40,
                                    where match: (AXUIElement) -> Bool) -> [AXUIElement] {
        var results: [AXUIElement] = []
        func walk(_ node: AXUIElement, _ depth: Int) {
            if match(node) { results.append(node) }
            guard depth < maxDepth else { return }
            for child in children(node) { walk(child, depth + 1) }
        }
        walk(element, 0)
        return results
    }

    @discardableResult
    nonisolated static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    private nonisolated static func value(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return value
    }
}
