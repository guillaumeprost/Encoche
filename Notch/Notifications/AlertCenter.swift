import AppKit
import Observation
import SwiftUI

/// Une notification affichée dans l'encoche, façon Dynamic Island.
struct NotchAlert: Identifiable {
    enum Icon {
        case app(bundleID: String)
        case symbol(String, Color)
    }

    enum Action {
        case openApp(bundleID: String)
        case openURL(URL)
        case run(@MainActor () -> Void)
    }

    /// Bouton d'action (ex. Autoriser / Refuser une demande de Claude Code).
    struct Button: Identifiable {
        enum Role { case primary, normal, destructive }
        let id = UUID()
        let label: String
        let role: Role
        let action: @MainActor () -> Void
    }

    var id = UUID()
    let icon: Icon
    /// Nom de l'app ou du module d'origine.
    let source: String
    let title: String
    let body: String?
    var date = Date()
    var action: Action?
    /// Une notification avec des boutons attend une réponse : elle reste affichée.
    var buttons: [Button] = []

    var isPersistent: Bool { !buttons.isEmpty }
}

/// File d'attente des notifications : une seule affichée à la fois, environ 5 secondes,
/// prolongée tant que la souris est dessus.
@Observable
@MainActor
final class AlertCenter {
    private static let displayDuration: Duration = .seconds(5)
    private static let afterHoverDuration: Duration = .seconds(2)
    /// Au-delà, une notification restée en file n'a plus d'intérêt.
    private static let maxAge: TimeInterval = 60

    private(set) var current: NotchAlert?
    /// Notifications reçues, plus récentes d'abord. En mémoire seulement : rien n'est écrit sur le disque.
    private(set) var history: [NotchAlert] = []
    private(set) var unreadCount = 0
    private static let historyLimit = 100
    private var queue: [NotchAlert] = []
    /// Écrans dont la notification est survolée (une encoche par écran).
    private var hoveringSources: Set<ObjectIdentifier> = []
    /// La notification affichée est survolée (elle reste alors à l'écran et se déplie).
    private(set) var isHovered = false
    private var dismissTask: Task<Void, Never>?

    /// Fichier de l'historique ; `nil` : rien n'est lu ni écrit (tests).
    private let historyURL: URL?

    init(historyURL: URL? = HistoryStore.defaultURL) {
        self.historyURL = historyURL
        if let historyURL { history = HistoryStore.load(from: historyURL) }
    }

    private func saveHistory() {
        if let historyURL { HistoryStore.save(history, to: historyURL) }
    }

    /// Apps dont les notifications relayées sont ignorées jusqu'à une date (doublons).
    private var mutedApps: [String: Date] = [:]

    /// Ignore un moment les notifications relayées d'une app, et retire celles qui viennent
    /// d'arriver : Encoche affiche déjà la même information (ex. fin de tâche de Claude).
    func muteRelayedNotifications(from bundleID: String, for seconds: TimeInterval = 20) {
        mutedApps[bundleID] = Date().addingTimeInterval(seconds)
        let recent = Date().addingTimeInterval(-seconds)
        let isDuplicate: (NotchAlert) -> Bool = { alert in
            if case .app(let id) = alert.icon { return id == bundleID && alert.date > recent }
            return false
        }
        queue.removeAll(where: isDuplicate)
        let before = history.count
        history.removeAll(where: isDuplicate)
        if history.count != before { saveHistory() }
        if let current, isDuplicate(current) { dismiss() }
    }

    /// Notifications tues (mode Concentration) : rangées dans l'historique sans s'afficher.
    private var silencedIDs: Set<UUID> = []

    /// `silently` : seulement dans l'historique, comme une notification que la Concentration fait taire.
    func post(_ alert: NotchAlert, silently: Bool = false) {
        if case .app(let bundleID) = alert.icon, let until = mutedApps[bundleID], until > Date() { return }
        // Les demandes qui attendent une réponse n'ont pas leur place dans l'historique.
        if !alert.isPersistent {
            history.insert(alert, at: 0)
            if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
            unreadCount += 1
            saveHistory()
        }
        guard !silently || alert.isPersistent else {
            silencedIDs.insert(alert.id)
            return
        }
        queue.append(alert)
        if current == nil { showNext() }
    }

    /// Une notification tue s'affiche quand même en bannière (app autorisée pendant la
    /// Concentration, notification urgente) : on l'affiche aussi dans l'encoche.
    /// `false` s'il n'y en a pas avec ce titre il y a moins de `seconds` secondes.
    func presentSilenced(title: String, within seconds: TimeInterval = 10) -> Bool {
        guard
            let alert = history.first(where: {
                silencedIDs.contains($0.id) && $0.title == title && Date().timeIntervalSince($0.date) < seconds
            })
        else { return false }
        silencedIDs.remove(alert.id)
        queue.append(alert)
        if current == nil { showNext() }
        return true
    }

    func setHovering(_ hovering: Bool, from source: ObjectIdentifier) {
        let wasHovering = !hoveringSources.isEmpty
        if hovering { hoveringSources.insert(source) } else { hoveringSources.remove(source) }
        let isHovering = !hoveringSources.isEmpty
        if isHovered != isHovering { isHovered = isHovering }
        guard isHovering != wasHovering, let current, !current.isPersistent else { return }
        if isHovering {
            dismissTask?.cancel()
        } else {
            scheduleDismiss(after: Self.afterHoverDuration)
        }
    }

    /// Une notification avec ce titre est-elle arrivée il y a moins de `seconds` secondes ?
    func hasRecent(title: String, within seconds: TimeInterval = 10) -> Bool {
        history.contains { $0.title == title && Date().timeIntervalSince($0.date) < seconds }
    }

    /// Même question, avec le même texte.
    func hasRecent(title: String, body: String?, within seconds: TimeInterval = 10) -> Bool {
        history.contains { $0.title == title && $0.body == body && Date().timeIntervalSince($0.date) < seconds }
    }

    func markAllRead() {
        unreadCount = 0
    }

    func clearHistory() {
        history.removeAll()
        unreadCount = 0
        saveHistory()
    }

    func removeFromHistory(_ alert: NotchAlert) {
        history.removeAll { $0.id == alert.id }
        saveHistory()
    }

    /// Clic sur la notification : on exécute son action (ouvrir l'app…) et on la retire.
    func activate() {
        guard let alert = current, alert.action != nil else { return }
        perform(alert)
        dismiss()
    }

    /// Exécute l'action d'une notification (aussi depuis l'historique).
    func perform(_ alert: NotchAlert) {
        switch alert.action {
        case .openApp(let bundleID):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
        case .openURL(let url):
            NSWorkspace.shared.open(url)
        case .run(let block):
            block()
        case nil:
            break
        }
    }

    /// Clic sur un bouton de la notification.
    func press(_ button: NotchAlert.Button) {
        button.action()
        if current?.buttons.contains(where: { $0.id == button.id }) == true { dismiss() }
    }

    /// Retire une notification précise, affichée ou en file (demande tranchée ailleurs).
    func dismiss(alertID: UUID) {
        queue.removeAll { $0.id == alertID }
        if current?.id == alertID { dismiss() }
    }

    func dismiss() {
        dismissTask?.cancel()
        hoveringSources.removeAll()
        isHovered = false
        current = nil
        // Laisse l'encoche se replier avant d'afficher la suivante.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            if let self, self.current == nil { self.showNext() }
        }
    }

    private func showNext() {
        queue.removeAll { !$0.isPersistent && Date().timeIntervalSince($0.date) > Self.maxAge }
        guard !queue.isEmpty else { return }
        // Les demandes qui attendent une réponse passent devant.
        let index = queue.firstIndex(where: \.isPersistent) ?? 0
        current = queue.remove(at: index)
        if current?.isPersistent == false { scheduleDismiss(after: Self.displayDuration) }
    }

    private func scheduleDismiss(after duration: Duration) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }
}

// MARK: - Persistance de l'historique

/// Historique des notifications enregistré dans Application Support, pour le retrouver
/// après un redémarrage. Les actions internes (ex. ramener une session Claude) ne sont pas
/// enregistrables : seules l'ouverture d'une app ou d'une URL survivent.
enum HistoryStore {
    private struct Stored: Codable {
        var id: UUID
        var appBundleID: String?
        var symbol: String?
        var colorName: String?
        var source: String
        var title: String
        var body: String?
        var date: Date
        var openURL: URL?
    }

    private static let colors: [String: Color] = [
        "claude": .claude, "green": .green, "red": .red, "blue": .blue, "gray": .gray, "orange": .orange,
    ]

    static var defaultURL: URL { URL.appSupport.appendingPathComponent("notifications.json") }

    static func save(_ alerts: [NotchAlert], to url: URL) {
        let stored = alerts.map { alert -> Stored in
            var item = Stored(id: alert.id, source: alert.source, title: alert.title, body: alert.body, date: alert.date)
            switch alert.icon {
            case .app(let bundleID): item.appBundleID = bundleID
            case .symbol(let name, let color):
                item.symbol = name
                item.colorName = colors.first { $0.value == color }?.key
            }
            switch alert.action {
            case .openApp(let bundleID): item.appBundleID = item.appBundleID ?? bundleID
            case .openURL(let url): item.openURL = url
            default: break
            }
            return item
        }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load(from url: URL) -> [NotchAlert] {
        guard let data = try? Data(contentsOf: url),
            let stored = try? JSONDecoder().decode([Stored].self, from: data)
        else { return [] }
        return stored.map { item in
            let icon: NotchAlert.Icon =
                item.appBundleID.map { .app(bundleID: $0) }
                ?? .symbol(item.symbol ?? "bell.fill", item.colorName.flatMap { colors[$0] } ?? .gray)
            let action: NotchAlert.Action? =
                item.openURL.map { .openURL($0) }
                ?? item.appBundleID.map { .openApp(bundleID: $0) }
            return NotchAlert(
                id: item.id, icon: icon, source: item.source, title: item.title,
                body: item.body, date: item.date, action: action)
        }
    }
}
