import AppKit

/// Envoie une réponse à une session Claude Code, depuis l'encoche.
///
/// - Terminal et iTerm : le texte est tapé dans l'onglet de la session (retrouvé par son
///   terminal, `ttys…`), puis envoyé.
/// - Autres apps (app Claude, VS Code, Ghostty…) : rien ne permet de viser la bonne
///   conversation à coup sûr. L'app passe au premier plan et le texte est collé, sans
///   l'envoyer : tu vérifies et tu appuies sur Entrée.
@MainActor
enum ClaudeReply {
    enum Outcome: Equatable {
        case sent(app: String)
        case pasted(app: String)
        case failed(String)
    }

    private static let terminalID = "com.apple.Terminal"
    private static let iTermID = "com.googlecode.iterm2"

    static func send(_ text: String, toProcess pid: pid_t) async -> Outcome {
        // Une nouvelle ligne enverrait le message trop tôt dans le terminal.
        let message = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !message.isEmpty else { return .failed("Message vide") }
        guard let app = ProcessOwner.app(of: pid) else { return .failed("Session introuvable") }
        let appName = app.localizedName ?? "l'app"
        let tty = ProcessOwner.ttyPath(of: pid)

        switch (app.bundleIdentifier, tty) {
        case (iTermID, let tty?):
            // iTerm écrit directement dans la session, sans changer de fenêtre.
            let script = """
            tell application id "\(iTermID)"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                tell s to write text "\(escaped(message))" newline no
                                delay 0.25
                                tell s to write text ""
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return "missing"
            """
            return await AppleScriptRunner.run(script, cached: false)?.stringValue == "ok"
                ? .sent(app: appName) : .failed("Onglet iTerm introuvable")

        case (terminalID, let tty?):
            // Terminal : on affiche le bon onglet, puis on colle et on valide.
            let script = """
            tell application id "\(terminalID)"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected of t to true
                            set index of w to 1
                            activate
                            return "ok"
                        end if
                    end repeat
                end repeat
            end tell
            return "missing"
            """
            guard await AppleScriptRunner.run(script, cached: false)?.stringValue == "ok" else {
                return .failed("Onglet Terminal introuvable")
            }
            try? await Task.sleep(for: .milliseconds(250))
            await paste(message, thenReturn: true)
            return .sent(app: appName)

        default:
            guard app.activate() else { return .failed("Impossible d'ouvrir \(appName)") }
            try? await Task.sleep(for: .milliseconds(350))
            await paste(message, thenReturn: false)
            return .pasted(app: appName)
        }
    }

    // MARK: - Clavier

    /// Colle le texte avec ⌘V (le presse-papier est rétabli juste après), puis Entrée si demandé.
    private static func paste(_ text: String, thenReturn: Bool) async {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { result, type in
                result[type] = item.data(forType: type)
            }
        } ?? []

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        // Ignoré par l'historique du presse-papier d'Encoche.
        item.setString("", forType: .init("org.nspasteboard.ConcealedType"))
        pasteboard.writeObjects([item])

        press(key: 9, flags: .maskCommand) // V
        try? await Task.sleep(for: .milliseconds(300))
        if thenReturn { press(key: 36, flags: []) } // Entrée

        try? await Task.sleep(for: .milliseconds(400))
        pasteboard.clearContents()
        let restored = saved.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }

    private static func press(key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Outils

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
