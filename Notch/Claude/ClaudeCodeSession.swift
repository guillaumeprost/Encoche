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
    /// Début de la demande en cours (pour afficher depuis combien de temps Claude travaille).
    var workStartedAt: Date?
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

    /// Fichiers modifiés pendant la demande en cours (chemins complets, dans l'ordre).
    var editedFiles: [String] = []
    var linesAdded = 0
    var linesRemoved = 0
    /// Résultat des derniers tests lancés pendant la demande (`nil` : pas de tests).
    var testsPassed: Bool?

    /// Bilan de la demande : « 3 fichiers modifiés · +120 −40 · tests OK », ou `nil` sans changement.
    var changeSummary: String? {
        var parts: [String] = []
        if !editedFiles.isEmpty {
            let count = editedFiles.count
            parts.append(count == 1 ? "1 fichier modifié" : "\(count) fichiers modifiés")
            if linesAdded + linesRemoved > 0 { parts.append("+\(linesAdded) −\(linesRemoved)") }
        }
        if let testsPassed { parts.append(testsPassed ? "tests OK" : "tests en échec") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Remet à zéro le bilan au début d'une demande.
    mutating func resetChanges() {
        editedFiles = []
        linesAdded = 0
        linesRemoved = 0
        testsPassed = nil
    }

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

    /// « 45 s », « 3 min », « 1 h 05 » : durée de la demande en cours.
    static func elapsed(since start: Date, now: Date = Date()) -> String {
        let seconds = max(Int(now.timeIntervalSince(start)), 0)
        switch seconds {
        case ..<60: return "\(seconds) s"
        case ..<3600: return "\(seconds / 60) min"
        default: return String(format: "%d h %02d", seconds / 3600, (seconds % 3600) / 60)
        }
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
    /// Aperçu de la modification demandée (fichiers modifiés ou écrits).
    var diff: [ClaudeActivity.DiffLine]? { ClaudeActivity.diff(tool: toolName, input: input) }
}
