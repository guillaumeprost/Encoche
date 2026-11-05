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
        guard let container = find(in: window, where: { AX.string($0, kAXIdentifierAttribute) == "headerContainer" }),
              let table = find(in: container, where: { AX.role($0) == "AXTable" }) else { return .panelClosed }
        let rows = AX.elements(table, kAXRowsAttribute)
        // Lecture paresseuse, depuis la fin : les lignes hors de l'écran sont lentes à lire.
        return .entries(upcoming(fromLastRows: rows.reversed().lazy.map { texts(in: $0) }))
    }

    /// Morceaux à venir, d'après les textes des lignes de la table lus depuis la fin.
    ///
    /// Les morceaux à venir sont à la fin, sous des titres de section (« À suivre »,
    /// « Poursuivre la lecture ») ; au-dessus, c'est l'historique. On s'arrête au plus tôt.
    nonisolated static func upcoming<Rows: Sequence>(fromLastRows rows: Rows) -> [Entry] where Rows.Element == [String] {
        var upcoming: [[String]] = []
        var pending: [[String]] = []
        var foundSection = false
        var readSinceSection = 0
        for (count, content) in rows.enumerated() {
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
        return upcoming.compactMap { row -> Entry? in
            // Les lignes à un seul texte sont des titres de section.
            guard row.count >= 2 else { return nil }
            let artist = row[1].components(separatedBy: " — ").first ?? row[1]
            return Entry(title: row[0], artist: artist)
        }
    }

    /// Ouvre le panneau de file d'attente dans Musique (bouton du mini-lecteur).
    nonisolated static func showPanel() {
        guard let window = musicWindow(),
              let button = find(in: window, where: { AX.string($0, kAXIdentifierAttribute) == "Music.miniPlayer.queueButton" }) else { return }
        AX.press(button)
    }

    // MARK: - Accessibilité

    private nonisolated static func musicWindow() -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first else { return nil }
        return AX.elements(AX.app(app.processIdentifier), kAXWindowsAttribute).first
    }

    /// Les listes (barre latérale, playlists…) ont des centaines de lignes : on n'y descend pas.
    private nonisolated static func find(in element: AXUIElement, where match: (AXUIElement) -> Bool) -> AXUIElement? {
        AX.first(in: element, maxDepth: 12, skipping: ["AXOutline", "AXTable", "AXList", "AXRow"], where: match)
    }

    /// Textes d'une ligne de la table : titre, puis « artiste — album ».
    private nonisolated static func texts(in row: AXUIElement) -> [String] {
        AX.collect(in: row, maxDepth: 4) { AX.role($0) == "AXStaticText" }.compactMap { text in
            let value = AX.string(text, kAXValueAttribute) ?? AX.string(text, kAXDescriptionAttribute) ?? ""
            return value.isEmpty ? nil : value
        }
    }
}
