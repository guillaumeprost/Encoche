import AppKit

/// Envoie une réponse à une session Claude Code, depuis l'encoche.
///
/// - Terminal et iTerm : le texte est tapé dans l'onglet de la session (retrouvé par son
///   terminal, `ttys…`), puis envoyé.
/// - App Claude : la conversation de la session est ouverte, le texte écrit dans son champ par
///   l'Accessibilité, puis envoyé ; un choix proposé (question, réponses) clique sur son bouton.
/// - Autres apps (VS Code, Ghostty…) : rien ne permet de viser la bonne conversation à coup
///   sûr. L'app passe au premier plan et le texte est collé, sans l'envoyer.
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

    /// `sessionTitle` (titre de la session dans l'app Claude) permet d'y viser la bonne conversation.
    /// `asChoice` : la réponse est un choix proposé (question, réponses) : dans l'app Claude, on
    /// clique sur le bouton de ce libellé. Jamais pour un texte libre.
    static func send(_ text: String, toProcess pid: pid_t, sessionTitle: String? = nil, asChoice: Bool = false) async -> Outcome {
        let message = sanitized(text)
        guard !message.isEmpty else { return .failed("Message vide") }
        guard let app = ProcessOwner.app(of: pid) else { return .failed("Session introuvable") }
        let appName = app.localizedName ?? "l'app"
        let tty = ProcessOwner.ttyPath(of: pid)

        // App Claude : si la réponse correspond à un bouton affiché (question, réponses proposées),
        // on clique dessus, exactement comme à la main.
        if asChoice, app.bundleIdentifier == claudeAppID,
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
                                tell s to write text "\(AppleScriptRunner.escape(message))" newline no
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
            await paste(message, thenReturn: true, to: pid_t(app.processIdentifier))
            return .sent(app: appName)

        case (claudeAppID, _):
            // App Claude : on ouvre la conversation de la session, on écrit dans son champ par
            // l'Accessibilité, puis Entrée. Sans pouvoir vérifier la conversation, on colle sans envoyer.
            let appPID = pid_t(app.processIdentifier)
            // Au premier plan d'abord : sur un autre bureau, ses fenêtres sont invisibles pour l'Accessibilité.
            guard app.activate() else { return .failed("Impossible d'ouvrir \(appName)") }
            try? await Task.sleep(for: .milliseconds(500))
            await Task.detached { raiseMainWindow(ofAppWith: appPID) }.value
            let typed = await Task.detached { typeInComposer(message, inAppWith: appPID, conversation: sessionTitle) }.value
            guard typed else {
                await paste(message, thenReturn: false, to: appPID)
                return .pasted(app: appName)
            }
            try? await Task.sleep(for: .milliseconds(200))
            press(key: 36, flags: [], to: appPID) // Entrée
            return .sent(app: appName)

        default:
            guard app.activate() else { return .failed("Impossible d'ouvrir \(appName)") }
            try? await Task.sleep(for: .milliseconds(350))
            await paste(message, thenReturn: false, to: pid_t(app.processIdentifier))
            return .pasted(app: appName)
        }
    }

    /// Démarre une nouvelle conversation dans l'app Claude, en mode Chat (pas Code), avec ce message.
    static func startNewConversation(_ text: String) async -> Outcome {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return .failed("Message vide") }
        var app = NSRunningApplication.runningApplications(withBundleIdentifier: claudeAppID).first
        if app == nil {
            // App fermée : on l'ouvre et on lui laisse le temps de démarrer.
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: claudeAppID) else {
                return .failed("App Claude introuvable")
            }
            app = try? await NSWorkspace.shared.openApplication(at: url, configuration: .init())
            try? await Task.sleep(for: .seconds(3))
        }
        guard let app, app.activate() else { return .failed("Impossible d'ouvrir Claude") }
        let appPID = pid_t(app.processIdentifier)
        try? await Task.sleep(for: .milliseconds(500))
        await Task.detached { raiseMainWindow(ofAppWith: appPID) }.value
        // Mode « Chat » d'abord : en mode Code, ⌘N ouvrirait une session de code.
        if await Task.detached(operation: { selectChatMode(inAppWith: appPID) }).value {
            try? await Task.sleep(for: .milliseconds(700))
        }
        press(key: 45, flags: .maskCommand, to: appPID) // ⌘N
        try? await Task.sleep(for: .milliseconds(1200))

        let typed = await Task.detached { typeInVisibleComposer(message, inAppWith: appPID) }.value
        guard typed else {
            await paste(message, thenReturn: false, to: appPID)
            return .pasted(app: "Claude")
        }
        try? await Task.sleep(for: .milliseconds(200))
        press(key: 36, flags: [], to: appPID) // Entrée
        return .sent(app: "Claude")
    }

    /// Clique sur le mode « Chat et Cowork » de l'app Claude. Renvoie `true` s'il a fallu changer.
    nonisolated static func selectChatMode(inAppWith appPID: pid_t) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let app = AX.app(appPID, manual: true)
        for _ in 0..<6 {
            // Le nom du mode est dans la description : le titre est vide.
            if let window = AX.mainWindow(of: app),
               let chat = AX.first(in: window, where: { AX.role($0) == "AXRadioButton" && AX.label(of: $0).hasPrefix("Chat") }) {
                var selected: AnyObject?
                AXUIElementCopyAttributeValue(chat, kAXValueAttribute as CFString, &selected)
                if (selected as? Int) == 1 { return false }
                return AX.press(chat)
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }

    /// Écrit dans le champ vide de la conversation affichée (la nouvelle, après ⌘N), sans
    /// toucher au brouillon d'une autre conversation.
    nonisolated static func typeInVisibleComposer(_ text: String, inAppWith appPID: pid_t) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let app = AX.app(appPID, manual: true)
        for _ in 0..<10 {
            if let window = AX.mainWindow(of: app) {
                for area in AX.collect(in: window, where: { AX.role($0) == "AXWebArea" }).reversed() {
                    guard let field = AX.first(in: area, where: { AX.role($0) == "AXTextArea" }),
                          (AX.string(field, kAXValueAttribute) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    else { continue }
                    AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                    return AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, text as CFString) == .success
                }
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
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
        let app = AX.app(appPID, manual: true)
        for _ in 0..<8 {
            let matches = AX.elements(app, kAXWindowsAttribute).flatMap { window in
                AX.collect(in: window, maxDepth: 60) { element in
                    let role = AX.role(element)
                    guard role == "AXButton" || role == "AXCheckBox" else { return false }
                    return matchesChoice(role: role, title: AX.label(of: element), label: label)
                }
            }
            if let match = matches.last {
                guard AX.press(match) else { return false }
                // Une réponse de question est une case à cocher : on valide ensuite avec « Envoyer ».
                if AX.role(match) == "AXCheckBox" {
                    Thread.sleep(forTimeInterval: 0.15)
                    guard let send = submitButton(near: match) else { return false }
                    return AX.press(send)
                }
                return true
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    /// Le contrôle correspond-il au choix ? Bouton : libellé exact. Case de question :
    /// « libellé description », le libellé suffit.
    nonisolated static func matchesChoice(role: String?, title: String, label: String) -> Bool {
        role == "AXCheckBox" ? title == label || title.hasPrefix(label + " ") : title == label
    }

    /// Écrit le texte dans le champ de saisie de la conversation de la session (app Claude).
    nonisolated static func typeInComposer(_ text: String, inAppWith appPID: pid_t, conversation title: String?) -> Bool {
        guard let composer = composer(inAppWith: appPID, conversation: title) else { return false }
        AXUIElementSetAttributeValue(composer, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        // On remplace la valeur du champ (en gardant un éventuel brouillon) : c'est ce que l'app
        // prend en compte, une insertion « comme une saisie » est ignorée.
        let draft = AX.string(composer, kAXValueAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let value = draft.isEmpty ? text : draft + " " + text
        return AXUIElementSetAttributeValue(composer, kAXValueAttribute as CFString, value as CFString) == .success
    }

    /// Fenêtre de l'app au premier plan et principale : c'est elle qui reçoit le clavier.
    nonisolated static func raiseMainWindow(ofAppWith appPID: pid_t) {
        let app = AX.app(appPID)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        guard let window = AX.mainWindow(of: app) else { return }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
    }

    /// Champ de saisie de la conversation de la session dans l'app Claude (au besoin en cliquant
    /// sur son entrée dans la barre latérale). `nil` si la bonne conversation n'a pas pu être vérifiée.
    nonisolated static func composer(inAppWith appPID: pid_t, conversation title: String?) -> AXUIElement? {
        guard AXIsProcessTrusted(), let title, !title.isEmpty else { return nil }
        let app = AX.app(appPID, manual: true)

        for attempt in 0..<10 {
            guard let window = AX.mainWindow(of: app) else {
                Thread.sleep(forTimeInterval: 0.2)
                continue
            }
            // La fenêtre contient plusieurs zones web : on prend celle de la conversation, reconnue
            // à son titre (« Titre - Claude Code ») ou, à défaut, à son en-tête.
            let webAreas = AX.collect(in: window) { AX.role($0) == "AXWebArea" }
            let conversation = webAreas.first { matchesConversation(shown: AX.label(of: $0), title: title) }
                ?? webAreas.first { area in
                    AX.first(in: area, where: { AX.role($0) == "AXHeading" && AX.string($0, kAXTitleAttribute) == title }) != nil
                }
            if let conversation {
                return AX.first(in: conversation, where: { AX.role($0) == "AXTextArea" })
            }
            // Autre conversation affichée : on clique une fois sur celle de la session.
            if attempt == 1, let entry = AX.first(in: window, where: {
                AX.role($0) == "AXButton" && AX.string($0, kAXTitleAttribute) == title
            }) {
                AX.press(entry)
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return nil
    }

    /// La page affichée est-elle la conversation de la session ? (« Titre - Claude Code »)
    nonisolated static func matchesConversation(shown: String, title: String) -> Bool {
        shown == title || shown.hasPrefix(title + " - ")
    }

    /// Bouton « Envoyer » de la question qui contient cette case.
    private nonisolated static func submitButton(near element: AXUIElement) -> AXUIElement? {
        let titles: Set<String> = ["Envoyer", "Submit", "Send"]
        var ancestor = element
        for _ in 0..<5 {
            guard let parent = AX.element(ancestor, kAXParentAttribute) else { return nil }
            ancestor = parent
            if let send = AX.first(in: ancestor, maxDepth: 6, where: {
                AX.role($0) == "AXButton" && titles.contains(AX.label(of: $0))
            }) {
                return send
            }
        }
        return nil
    }

    // MARK: - Clavier

    /// Colle le texte avec ⌘V (le presse-papier est rétabli juste après), puis Entrée si demandé.
    /// Les touches sont envoyées à l'app visée (`pid`) : l'encoche, où l'on vient de taper,
    /// garde sinon le clavier et les recevrait.
    private static func paste(_ text: String, thenReturn: Bool, to pid: pid_t) async {
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

        press(key: 9, flags: .maskCommand, to: pid) // V
        try? await Task.sleep(for: .milliseconds(300))
        if thenReturn { press(key: 36, flags: [], to: pid) } // Entrée

        try? await Task.sleep(for: .milliseconds(400))
        pasteboard.clearContents()
        let restored = saved.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }

    private static func press(key: CGKeyCode, flags: CGEventFlags, to pid: pid_t) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = flags
            event?.postToPid(pid)
        }
    }

    // MARK: - Outils

    /// Message sur une ligne : un retour à la ligne l'enverrait trop tôt dans un terminal.
    nonisolated static func sanitized(_ text: String) -> String {
        text.replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
