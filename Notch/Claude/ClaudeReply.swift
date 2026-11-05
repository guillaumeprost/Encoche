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
    static let claudeAppID = "com.anthropic.claudefordesktop"
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

        // App Claude : si la réponse correspond à un bouton affiché (question, réponses proposées),
        // on clique dessus, exactement comme à la main.
        if app.bundleIdentifier == claudeAppID,
           await Task.detached(operation: { pressButton(labeled: message, inAppWith: pid_t(app.processIdentifier)) }).value {
            return .sent(app: appName)
        }

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

    /// La session tourne dans l'app Claude.
    static func isInClaudeApp(_ pid: pid_t) -> Bool {
        ProcessOwner.app(of: pid)?.bundleIdentifier == claudeAppID
    }

    // MARK: - Boutons de l'app Claude

    /// Clique sur le bouton de ce libellé dans l'app Claude (le plus récent s'il y en a plusieurs).
    /// L'app (Electron) n'expose son contenu à l'Accessibilité qu'une fois qu'on le lui demande :
    /// on l'active, puis on réessaie un court instant.
    nonisolated static func pressButton(labeled label: String, inAppWith appPID: pid_t) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let app = AXUIElementCreateApplication(appPID)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        for _ in 0..<8 {
            var matches: [AXUIElement] = []
            for window in axChildren(app, kAXWindowsAttribute) {
                collectButtons(labeled: label, in: window, into: &matches)
            }
            if let match = matches.last {
                guard AXUIElementPerformAction(match, kAXPressAction as CFString) == .success else { return false }
                // Une réponse de question est une case à cocher : on valide ensuite avec « Envoyer ».
                if axString(match, kAXRoleAttribute) == "AXCheckBox" {
                    Thread.sleep(forTimeInterval: 0.15)
                    guard let send = submitButton(near: match) else { return false }
                    return AXUIElementPerformAction(send, kAXPressAction as CFString) == .success
                }
                return true
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    private nonisolated static func collectButtons(labeled label: String, in element: AXUIElement,
                                                   into matches: inout [AXUIElement], depth: Int = 0) {
        switch axString(element, kAXRoleAttribute) {
        case "AXButton":
            // Réponses proposées : boutons au libellé exact.
            if axString(element, kAXTitleAttribute) == label || axString(element, kAXDescriptionAttribute) == label {
                matches.append(element)
            }
        case "AXCheckBox":
            // Question : « libellé description » ; le libellé suffit.
            if let title = axString(element, kAXTitleAttribute), title == label || title.hasPrefix(label + " ") {
                matches.append(element)
            }
        default:
            break
        }
        guard depth < 60 else { return }
        for child in axChildren(element, kAXChildrenAttribute) {
            collectButtons(labeled: label, in: child, into: &matches, depth: depth + 1)
        }
    }

    /// Bouton « Envoyer » de la question qui contient cette case.
    private nonisolated static func submitButton(near element: AXUIElement) -> AXUIElement? {
        let titles: Set<String> = ["Envoyer", "Submit", "Send"]
        var ancestor = element
        for _ in 0..<5 {
            var parent: AnyObject?
            guard AXUIElementCopyAttributeValue(ancestor, kAXParentAttribute as CFString, &parent) == .success,
                  let next = parent else { return nil }
            ancestor = next as! AXUIElement
            var found: AXUIElement?
            func search(_ node: AXUIElement, _ depth: Int) {
                guard found == nil else { return }
                if axString(node, kAXRoleAttribute) == "AXButton", let title = axString(node, kAXTitleAttribute)
                    ?? axString(node, kAXDescriptionAttribute), titles.contains(title) {
                    found = node
                    return
                }
                if depth < 6 { axChildren(node, kAXChildrenAttribute).forEach { search($0, depth + 1) } }
            }
            search(ancestor, 0)
            if let found { return found }
        }
        return nil
    }

    private nonisolated static func axString(_ element: AXUIElement, _ name: String) -> String? {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return value as? String
    }

    private nonisolated static func axChildren(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return value as? [AXUIElement] ?? []
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
