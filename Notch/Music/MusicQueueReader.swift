import AppKit

/// Lit la vraie file d'attente de Musique (« À suivre », « Poursuivre la lecture ») dans son
/// panneau de file d'attente, via l'Accessibilité : aucune API ne la donne autrement.
///
/// Le panneau doit être ouvert dans la fenêtre de Musique ; `showPanel()` l'ouvre.
/// Structure lue : une table avec « Historique » et les morceaux déjà joués, puis des sections
/// (lignes à un seul texte) suivies des morceaux à venir (titre, « artiste — album »).
/// Le morceau en cours n'y figure pas.
enum MusicQueueReader {
    struct Entry {
        let title: String
        let artist: String
    }

    enum Result {
        case entries([Entry])
        /// Le panneau de file d'attente est fermé dans Musique.
        case panelClosed
        case unavailable
    }

    /// Titre de la section d'historique (Musique en français ; « History » en anglais).
    private static let historyHeaders: Set<String> = ["Historique", "History"]

    nonisolated static func read() -> Result {
        guard AXIsProcessTrusted(), let window = musicWindow() else { return .unavailable }
        guard let container = find(in: window, where: { identifier($0) == "headerContainer" }),
              let table = find(in: container, where: { role($0) == "AXTable" }) else { return .panelClosed }

        // Les morceaux à venir sont à la fin, sous des titres de section (« À suivre »,
        // « Poursuivre la lecture ») ; au-dessus, c'est l'historique. On remonte depuis la fin :
        // les lignes hors de l'écran sont lentes à lire, on s'arrête donc au plus tôt.
        let rows = (attribute(table, kAXRowsAttribute) as? [AXUIElement]) ?? children(table)
        var upcoming: [[String]] = []
        var pending: [[String]] = []
        var foundSection = false
        var readSinceSection = 0
        for (count, row) in rows.reversed().enumerated() {
            let content = texts(in: row)
            if content.count == 1 {
                if historyHeaders.contains(content[0]) { break }
                // Les lignes lues depuis la fin appartiennent à cette section.
                upcoming.insert(contentsOf: pending, at: 0)
                pending = []
                foundSection = true
                readSinceSection = 0
                continue
            }
            pending.insert(content, at: 0)
            readSinceSection += 1
            // Après une section, une autre (« À suivre ») ne peut venir que peu au-dessus.
            if foundSection, readSinceSection > 25 { break }
            if !foundSection, count > 60 { break }
        }
        let entries = upcoming.compactMap { row -> Entry? in
            // Les lignes à un seul texte sont des titres de section.
            guard row.count >= 2 else { return nil }
            let artist = row[1].components(separatedBy: " — ").first ?? row[1]
            return Entry(title: row[0], artist: artist)
        }
        return .entries(entries)
    }

    /// Ouvre le panneau de file d'attente dans Musique (bouton du mini-lecteur).
    nonisolated static func showPanel() {
        guard let window = musicWindow(),
              let button = find(in: window, where: { identifier($0) == "Music.miniPlayer.queueButton" }) else { return }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
    }

    // MARK: - Accessibilité

    private nonisolated static func musicWindow() -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        return (attribute(element, kAXWindowsAttribute) as? [AXUIElement])?.first
    }

    private nonisolated static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return value
    }

    private nonisolated static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private nonisolated static func role(_ element: AXUIElement) -> String? {
        attribute(element, kAXRoleAttribute) as? String
    }

    private nonisolated static func identifier(_ element: AXUIElement) -> String? {
        attribute(element, kAXIdentifierAttribute) as? String
    }

    private nonisolated static func find(in element: AXUIElement, where match: (AXUIElement) -> Bool, depth: Int = 0) -> AXUIElement? {
        if match(element) { return element }
        // Les listes (barre latérale, playlists…) ont des centaines de lignes : on n'y descend pas.
        guard depth < 12, !["AXOutline", "AXTable", "AXList", "AXRow"].contains(role(element) ?? "") || depth == 0 else { return nil }
        for child in children(element) {
            if let found = find(in: child, where: match, depth: depth + 1) { return found }
        }
        return nil
    }

    private nonisolated static func texts(in element: AXUIElement, depth: Int = 0) -> [String] {
        var out: [String] = []
        if role(element) == "AXStaticText",
           let value = attribute(element, kAXValueAttribute) as? String ?? attribute(element, kAXDescriptionAttribute) as? String,
           !value.isEmpty {
            out.append(value)
        }
        if depth < 4 { for child in children(element) { out += texts(in: child, depth: depth + 1) } }
        return out
    }
}
