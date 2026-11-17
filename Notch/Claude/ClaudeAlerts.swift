import Foundation

/// Notifications de l'encoche pour Claude Code : demandes de permission, questions,
/// session qui t'attend et fin de tâche.
@MainActor
enum ClaudeAlerts {
    typealias Decide = @MainActor (PendingPermission.Decision) -> Void
    typealias Focus = @MainActor () -> Void
    /// Ouvre la session dans l'encoche (onglet Claude) : détail, aperçu et réponse en entier.
    typealias Open = @MainActor () -> Void

    /// Demande de permission : Refuser, Terminal, Toujours (si Claude Code le propose), Autoriser.
    static func permission(
        _ permission: PendingPermission, decide: @escaping Decide, focus: @escaping Focus, open: @escaping Open
    ) -> NotchAlert {
        var alert = NotchAlert(
            icon: .symbol("hand.raised.fill", .claude),
            source: "Claude Code",
            title: "\(permission.projectName) demande : \(permission.toolName)",
            // Ce que « Toujours » autoriserait, pour décider en connaissance de cause.
            body: [permission.summary, permission.alwaysDescription.map { "Toujours : \($0)" }].compactMap { $0 }
                .joined(separator: "\n"),
            action: .run(open)
        )
        var buttons: [NotchAlert.Button] = [
            .init(label: "Refuser", role: .destructive) { decide(.deny) },
            .init(label: "Terminal", role: .normal) { decide(.terminal) },
        ]
        if permission.canAllowAlways {
            buttons.append(.init(label: "Toujours", role: .normal) { decide(.allowAlways) })
        }
        buttons.append(.init(label: "Autoriser", role: .primary) { decide(.allow) })
        alert.buttons = buttons
        return alert
    }

    /// Question de Claude à une seule réponse : la question et ses choix.
    /// Plusieurs questions ou choix multiples : `nil`, la réponse se fait dans le terminal.
    static func question(_ permission: PendingPermission, decide: @escaping Decide, focus: @escaping Focus) -> NotchAlert? {
        guard let (text, labels) = ClaudeCodeMonitor.singleQuestion(in: permission.input) else { return nil }
        var alert = NotchAlert(
            icon: .symbol("questionmark.bubble.fill", .claude),
            source: "Claude Code",
            title: "\(permission.projectName) te demande",
            body: text,
            action: .run(focus)
        )
        let other = NotchAlert.Button(label: "Autre…", role: .normal) {
            decide(.terminal)
            focus()
        }
        alert.buttons = [other] + optionButtons(labels) { decide(.answer($0)) }
        return alert
    }

    /// Session qui attend quelque chose de toi (message de Claude Code).
    static func waiting(project: String, message: String, focus: @escaping Focus) -> NotchAlert {
        NotchAlert(
            icon: .symbol("hand.raised.fill", .claude),
            source: "Claude Code",
            title: "\(project) t'attend",
            body: message.isEmpty ? nil : message,
            action: .run(focus)
        )
    }

    /// Fin de tâche avec le début de la réponse de Claude ; s'il propose des réponses,
    /// sa question et un bouton par réponse (3 au plus).
    static func done(
        _ session: ClaudeCodeSession, reply: String?, choose: @escaping @MainActor (String) -> Void,
        focus: @escaping Focus, open: @escaping Open
    ) -> NotchAlert {
        let name = session.title ?? session.projectName
        guard let choices = session.choices else {
            // Un clic ouvre la réponse en entier dans l'encoche.
            return NotchAlert(
                icon: .symbol("checkmark", .green),
                source: session.projectName,
                title: "Terminé · \(name)",
                body: [session.changeSummary, reply.map(ClaudeCodeMonitor.plainSummary)].compactMap { $0 }
                    .joined(separator: " — "),
                action: .run(open)
            )
        }
        var alert = NotchAlert(
            icon: .symbol("questionmark.bubble.fill", .claude),
            source: session.projectName,
            // La question en entier : c'est à elle que répondent les boutons.
            title: "\(name) te demande",
            body: choices.question,
            action: .run(open)
        )
        alert.buttons = [.init(label: "Plus tard", role: .normal) {}] + optionButtons(Array(choices.options.prefix(3)), choose)
        return alert
    }

    /// Un bouton par réponse proposée, la première mise en avant.
    private static func optionButtons(
        _ labels: [String], _ choose: @escaping @MainActor (String) -> Void
    ) -> [NotchAlert.Button] {
        labels.enumerated().map { index, label in
            .init(label: label, role: index == 0 ? .primary : .normal) { choose(label) }
        }
    }
}
