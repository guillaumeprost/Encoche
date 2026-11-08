import Foundation

struct ClaudeCodeSession: Identifiable, Equatable {
    enum State: Equatable {
        case idle
        case working
        /// En attente de toi (permission à accorder, question posée…).
        case waiting
        case done
        /// Session fermée, ou retrouvée dans l'historique au lancement.
        case inactive
    }

    let id: String
    var cwd: String
    var state: State
    var detail: String?
    var updatedAt: Date
    /// Processus Claude Code (envoyé par les hooks) : sert à retrouver son app.
    var pid: pid_t?
    /// Titre donné à la session par Claude Code (lu dans la transcription).
    var title: String?
    /// Dernière demande envoyée à Claude.
    var prompt: String?
    /// Plan de la tâche en cours (liste de tâches de Claude).
    var plan: [PlanItem] = []
    /// Agents lancés pendant la demande en cours.
    var agents: [SubAgent] = []
    /// Dernière réponse de Claude.
    var lastMessage: String?
    /// Réponses proposées par Claude à la fin de sa réponse (boutons de l'app Claude).
    var choices: Choices?

    struct Choices: Equatable {
        let question: String
        let options: [String]
    }
    var transcriptPath: String?

    struct PlanItem: Equatable, Identifiable {
        enum Status: Equatable { case pending, inProgress, completed }
        let id: Int
        var content: String
        var status: Status
    }

    struct SubAgent: Equatable, Identifiable {
        let id: String
        var name: String
        var isRunning: Bool
    }

    var planProgress: (done: Int, total: Int) {
        (plan.filter { $0.status == .completed }.count, plan.count)
    }

    var projectName: String { Self.projectName(for: cwd) }

    /// Nom du projet : le dossier de travail de la session.
    static func projectName(for cwd: String) -> String {
        // Un chemin vide désignerait le dossier courant de l'app.
        guard !cwd.isEmpty else { return "Claude Code" }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? "Claude Code" : name
    }

    /// Avancement du plan entre 0 et 1, ou `nil` sans plan.
    var planFraction: Double? {
        let progress = planProgress
        return progress.total > 0 ? Double(progress.done) / Double(progress.total) : nil
    }
}

/// Demande de permission de Claude Code en attente de ta décision dans l'encoche.
@MainActor
final class PendingPermission: Identifiable {
    enum Decision: Equatable {
        case allow
        /// Réponse choisie à une question de Claude (outil « AskUserQuestion »).
        case answer(String)
        /// Autoriser et ajouter la règle suggérée par Claude Code (plus de question la prochaine fois).
        case allowAlways
        case deny
        /// Ne rien décider ici : Claude Code poursuit avec sa demande habituelle dans le terminal.
        case terminal
    }

    let id = UUID()
    let sessionID: String
    let projectName: String
    let toolName: String
    let summary: String
    /// Mises à jour de permissions suggérées par Claude Code (« toujours autoriser »).
    let suggestions: [[String: Any]]
    /// Paramètres de l'outil (pour y ajouter la réponse d'une question).
    let input: [String: Any]
    let reply: HookReply
    var alertID: UUID?
    /// Pour vérifier dans la conversation si la demande a été tranchée ailleurs (app Claude, terminal).
    var toolUseID: String?

    init(
        sessionID: String, projectName: String, toolName: String, summary: String,
        suggestions: [[String: Any]], input: [String: Any] = [:], reply: HookReply
    ) {
        self.input = input
        self.sessionID = sessionID
        self.projectName = projectName
        self.toolName = toolName
        self.summary = summary
        self.suggestions = suggestions
        self.reply = reply
    }

    var canAllowAlways: Bool { !suggestions.isEmpty }
}
