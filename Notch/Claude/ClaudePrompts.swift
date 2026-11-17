import Foundation

/// Demandes que l'encoche prépare pour Claude (presse-papier, étagère, notifications, réunions,
/// briefing du matin). Chacune a un libellé court, affiché dans l'onglet Claude à la place du texte
/// complet envoyé.
enum ClaudePrompts {
    struct Request: Equatable {
        let label: String
        let prompt: String
        var files: [URL] = []
    }

    /// Ce qu'on peut demander sur un texte copié.
    enum TextAction: CaseIterable {
        case explain, translate, fix, debug

        var title: String {
            switch self {
            case .explain: "Expliquer"
            case .translate: "Traduire"
            case .fix: "Corriger"
            case .debug: "Pourquoi ça plante ?"
            }
        }

        var symbol: String {
            switch self {
            case .explain: "lightbulb"
            case .translate: "character.bubble"
            case .fix: "wand.and.stars"
            case .debug: "ladybug"
            }
        }
    }

    /// Le texte ressemble à une erreur, une trace de plantage ou une sortie de compilateur.
    static func looksLikeError(_ text: String) -> Bool {
        let markers = [
            "error:", "error[", "exception", "traceback (most recent call last)", "fatal error", "panic:",
            "stack trace", "segmentation fault", "uncaught", "failed with exit code", "npm err!", "undefined is not",
            "cannot find", "nullpointerexception", "at com.", "    at ",
        ]
        let lower = text.lowercased()
        return markers.contains { lower.contains($0) }
    }

    /// Actions proposées pour un texte : la recherche de panne d'abord quand c'est une erreur.
    static func textActions(for text: String) -> [TextAction] {
        looksLikeError(text) ? [.debug, .explain, .translate] : [.explain, .translate, .fix]
    }

    static func text(_ action: TextAction, _ text: String) -> Request {
        let excerpt = String(text.prefix(12_000))
        let preview = shorten(text, 40)
        switch action {
        case .explain:
            return Request(label: "Expliquer « \(preview) »", prompt: "Explique simplement ce texte, en quelques phrases :\n\n\(excerpt)")
        case .translate:
            return Request(
                label: "Traduire « \(preview) »",
                prompt: """
                    Traduis ce texte. S'il est en français, traduis-le en anglais ; sinon, en français. \
                    Donne seulement la traduction :

                    \(excerpt)
                    """)
        case .fix:
            return Request(
                label: "Corriger « \(preview) »",
                prompt: """
                    Corrige l'orthographe, la grammaire et la ponctuation de ce texte sans changer son sens ni \
                    sa langue. Donne seulement le texte corrigé :

                    \(excerpt)
                    """)
        case .debug:
            return Request(
                label: "Pourquoi ça plante ? « \(preview) »",
                prompt: """
                    Voici une erreur que je viens de copier. Dis-moi en une phrase ce qui se passe, la cause la plus \
                    probable, puis comment la corriger :

                    \(excerpt)
                    """)
        }
    }

    /// Une image (capture, image copiée) : la décrire et en tirer l'essentiel.
    static func image(_ url: URL) -> Request {
        Request(
            label: "Décrire \(url.lastPathComponent)",
            prompt: """
                Lis l'image \(url.path). Dis en quelques phrases ce qu'elle montre ; s'il y a du texte, une \
                erreur ou des données, donne l'essentiel.
                """,
            files: [url])
    }

    /// Un ou plusieurs fichiers : les résumer.
    static func files(_ urls: [URL]) -> Request {
        let list = urls.prefix(5).map { "- \($0.path)" }.joined(separator: "\n")
        let label = urls.count == 1 ? "Résumer \(urls[0].lastPathComponent)" : "Résumer \(urls.count) fichiers"
        return Request(
            label: label,
            prompt: "Lis ces fichiers et résume en quelques points ce qu'ils contiennent :\n\(list)",
            files: Array(urls.prefix(5)))
    }

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp"]

    /// Image ou autre fichier, selon l'extension.
    static func file(_ url: URL) -> Request {
        imageExtensions.contains(url.pathExtension.lowercased()) ? image(url) : files([url])
    }

    // MARK: - Notifications

    struct NotificationLine: Equatable {
        let source: String
        let title: String
        let body: String?
        let date: Date
    }

    static func notifications(_ lines: [NotificationLine]) -> Request {
        let text = lines.prefix(40).map { line in
            let time = line.date.formatted(date: .omitted, time: .shortened)
            return "- \(time) · \(line.source) · \(line.title)" + (line.body.map { " : \(shorten($0, 200))" } ?? "")
        }.joined(separator: "\n")
        return Request(
            label: "Résumer \(min(lines.count, 40)) notifications",
            prompt: """
                Voici mes dernières notifications. Résume en quelques points ce qui s'est passé, en commençant \
                par ce qui demande une action de ma part. Regroupe par app quand c'est utile :

                \(text)
                """)
    }

    // MARK: - Réunions

    struct Meeting: Equatable {
        let title: String
        let start: Date
        let end: Date
        var location: String?
        var notes: String?
        var attendees: [String] = []
    }

    static func meeting(_ meeting: Meeting) -> Request {
        var details = ["Titre : \(meeting.title)", "Horaire : \(timeRange(meeting.start, meeting.end))"]
        if let location = meeting.location, !location.isEmpty { details.append("Lieu : \(location)") }
        if !meeting.attendees.isEmpty { details.append("Participants : \(meeting.attendees.prefix(15).joined(separator: ", "))") }
        if let notes = meeting.notes, !notes.isEmpty { details.append("Description :\n\(String(notes.prefix(4000)))") }
        return Request(
            label: "Préparer « \(shorten(meeting.title, 40)) »",
            prompt: """
                J'ai cette réunion bientôt. Aide-moi à la préparer : son objet probable, 3 points à avoir en tête \
                et 2 ou 3 questions utiles à poser. Reste court.

                \(details.joined(separator: "\n"))
                """)
    }

    // MARK: - Briefing du matin

    struct Briefing: Equatable {
        var events: [Meeting] = []
        var tasks: [String] = []
        var reminders: [String] = []

        var isEmpty: Bool { events.isEmpty && tasks.isEmpty && reminders.isEmpty }
    }

    static func briefing(_ day: Briefing, date: Date) -> Request {
        var sections: [String] = []
        if !day.events.isEmpty {
            sections.append(
                "Agenda :\n" + day.events.map { "- \(timeRange($0.start, $0.end)) · \($0.title)" }.joined(separator: "\n"))
        }
        if !day.tasks.isEmpty { sections.append("Tâches ClickUp :\n" + day.tasks.map { "- \($0)" }.joined(separator: "\n")) }
        if !day.reminders.isEmpty { sections.append("Rappels :\n" + day.reminders.map { "- \($0)" }.joined(separator: "\n")) }
        let today = date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        return Request(
            label: "Briefing du \(today)",
            prompt: """
                Nous sommes le \(today). Fais-moi un briefing de ma journée en 4 à 6 lignes : ce qui est \
                important, l'ordre conseillé, les créneaux libres pour travailler au calme, et ce qui est en \
                retard. Ton direct et encourageant.

                \(sections.joined(separator: "\n\n"))
                """)
    }

    /// « Revoir la maquette (en retard) · Design ».
    static func taskLine(_ task: ClickUpTask, now: Date = Date()) -> String {
        var state: String?
        if task.isOverdue(now: now) {
            state = "en retard"
        } else if let due = task.due, Calendar.current.isDate(due, inSameDayAs: now) {
            state = task.hasTime ? "aujourd'hui à \(due.formatted(date: .omitted, time: .shortened))" : "aujourd'hui"
        } else if task.isInProgress {
            state = "en cours"
        }
        return task.name + (state.map { " (\($0))" } ?? "") + " · \(task.listName)"
    }

    static func reminderLine(_ reminder: TodayReminder, now: Date = Date()) -> String {
        var line = reminder.title
        if reminder.isOverdue(now: now) {
            line += " (en retard)"
        } else if reminder.hasTime, let due = reminder.due {
            line += " (à \(due.formatted(date: .omitted, time: .shortened)))"
        }
        return line
    }

    // MARK: - Outils

    static func timeRange(_ start: Date, _ end: Date) -> String {
        "\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
    }

    private static func shorten(_ text: String, _ limit: Int) -> String {
        let line = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return line.count > limit ? String(line.prefix(limit)) + "…" : line
    }
}
