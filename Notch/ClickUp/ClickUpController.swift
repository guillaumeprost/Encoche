import AppKit
import Observation
import Security
import SwiftUI

/// Tâche ClickUp qui m'est assignée : en retard, pour aujourd'hui, ou en cours.
struct ClickUpTask: Identifiable, Equatable {
    let id: String
    let name: String
    let status: String
    /// Type du statut chez ClickUp : « open » (à faire), « custom » (en cours), « done », « closed ».
    let statusType: String
    let statusColor: Color
    /// Échéance ; sans heure quand la tâche est pour la journée.
    var due: Date?
    var hasTime: Bool
    /// 1 urgente, 2 haute, 3 normale, 4 basse.
    let priority: Int?
    let listID: String
    let listName: String
    /// Dernière modification (commentaire, statut, champ…), pour la section Activité.
    var updated: Date? = nil
    var isCompleted = false
    /// Statut d'avant la coche, rendu si on la décoche.
    var statusBeforeCompletion: String?

    var isInProgress: Bool { statusType == "custom" }

    /// Échéance un jour passé : rangée dans le groupe « En retard ».
    func isLate(now: Date) -> Bool {
        guard let due else { return false }
        return due < Calendar.current.startOfDay(for: now)
    }

    /// En retard : un jour passé, ou une heure passée aujourd'hui.
    func isOverdue(now: Date) -> Bool {
        guard let due, !isCompleted else { return false }
        return hasTime ? due < now : due < Calendar.current.startOfDay(for: now)
    }

    var priorityColor: Color? {
        switch priority {
        case 1: .red
        case 2: .orange
        default: nil
        }
    }
}

/// Un statut intermédiaire (type « custom ») de mes tâches, proposé dans le choix des statuts « en cours ».
struct ClickUpStatus: Identifiable, Hashable {
    let name: String
    let color: Color
    var id: String { name.lowercased() }
}

/// Liste ClickUp où créer une tâche.
struct ClickUpList: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    /// Espace (et dossier) de la liste, pour s'y retrouver dans le menu.
    let path: String
}

/// Mes tâches ClickUp, via l'API publique et un jeton personnel gardé dans le Trousseau.
/// Tout n'est actif que pendant que l'app ClickUp est ouverte.
@Observable
@MainActor
final class ClickUpController {
    enum State: Equatable {
        case noToken, loading, ready
        case failed(String)
    }

    nonisolated static let bundleID = "com.clickup.desktop-app"

    private(set) var isAppRunning = false
    private(set) var state: State
    private(set) var tasks: [ClickUpTask] = []
    /// Mes tâches les plus récemment modifiées (7 derniers jours), plus récentes d'abord.
    private(set) var recentTasks: [ClickUpTask] = []

    /// Section affichée dans l'onglet.
    enum Section: String, CaseIterable, Identifiable {
        case todo, activity, notifications
        var id: String { rawValue }
        var label: String {
            switch self {
            case .todo: "À faire"
            case .activity: "Activité"
            case .notifications: "Notifications"
            }
        }
    }

    /// Statuts intermédiaires vus dans mes tâches, pour choisir ceux qui comptent comme « en cours ».
    private(set) var customStatuses: [ClickUpStatus] = []
    /// Statuts (en minuscules) dont les tâches sans échéance s'affichent ; `nil` : tous les
    /// statuts intermédiaires, faute de choix (ClickUp ne distingue pas « à faire » d'« en cours »).
    private(set) var activeStatuses: Set<String>? =
        (UserDefaults.standard.array(forKey: "clickUpActiveStatuses") as? [String]).map(Set.init)
    {
        didSet { UserDefaults.standard.set(activeStatuses.map { Array($0).sorted() }, forKey: "clickUpActiveStatuses") }
    }
    /// Toutes mes tâches ouvertes de la dernière lecture, avant le tri du jour.
    @ObservationIgnored private var openTasks: [ClickUpTask] = []

    /// Groupe « En retard » déplié dans l'onglet.
    var showsLateTasks: Bool = UserDefaults.standard.bool(forKey: "clickUpShowsLateTasks") {
        didSet { UserDefaults.standard.set(showsLateTasks, forKey: "clickUpShowsLateTasks") }
    }

    /// Nouvelle échéance proposée au clic droit.
    enum Postponement: CaseIterable, Identifiable {
        case today, tomorrow, nextMonday, none
        var id: Self { self }
        var label: String {
            switch self {
            case .today: "Aujourd'hui"
            case .tomorrow: "Demain"
            case .nextMonday: "Lundi prochain"
            case .none: "Retirer l'échéance"
            }
        }
        var symbol: String {
            switch self {
            case .today: "star"
            case .tomorrow: "sunrise"
            case .nextMonday: "calendar.badge.clock"
            case .none: "calendar.badge.minus"
            }
        }
    }

    var section: Section = UserDefaults.standard.string(forKey: "clickUpSection").flatMap(Section.init) ?? .todo {
        didSet { UserDefaults.standard.set(section.rawValue, forKey: "clickUpSection") }
    }
    /// Nom du compte relié, affiché dans les réglages.
    private(set) var userName: String?

    /// Listes de mes espaces de travail, chargées à la première création de tâche.
    private(set) var lists: [ClickUpList] = []
    /// Liste où créer les tâches tapées dans l'encoche.
    var targetList: ClickUpList? = ClickUpController.savedTargetList() {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(targetList), forKey: "clickUpTargetList") }
    }
    private(set) var isCreating = false
    /// L'Accueil demande d'ouvrir l'onglet le champ prêt à taper.
    var wantsNewTaskFocus = false

    /// Appelé quand l'app ClickUp se ferme (pour quitter son onglet).
    @ObservationIgnored var onAppQuit: () -> Void = {}
    /// Pour les rappels d'échéance.
    @ObservationIgnored var alerts: AlertCenter?
    @ObservationIgnored var dueAlertsEnabled: () -> Bool = { true }
    /// Rappels déjà donnés (tâche + échéance), pour ne pas les répéter.
    @ObservationIgnored private var alertedKeys: Set<String> = []
    @ObservationIgnored private var dueTimer: Timer?

    @ObservationIgnored private var token: String?
    @ObservationIgnored private var userID: Int?
    @ObservationIgnored private var teamIDs: [String] = []
    /// Statut « terminé » de chaque liste, pour cocher une tâche.
    @ObservationIgnored private var doneStatusByList: [String: String] = [:]
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var refreshing = false
    /// Début de la dernière relecture.
    @ObservationIgnored private var lastRefresh: Date?
    /// Délai minimum entre deux relectures déclenchées en quittant ClickUp.
    nonisolated static let minimumRefreshInterval: TimeInterval = 15

    init() {
        // Le Trousseau peut demander l'autorisation (nouvelle compilation…) et attendre la
        // réponse : lu hors du fil principal, pour ne pas bloquer toute l'app en attendant.
        state = .loading
        Task { [weak self] in
            let saved = await Task.detached { Keychain.read() }.value
            self?.tokenLoaded(saved)
        }
        isAppRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == Self.bundleID else { return }
                let launched = name == NSWorkspace.didLaunchApplicationNotification
                MainActor.assumeIsolated { self?.setAppRunning(launched) }
            }
        }
        // En quittant ClickUp, on a sans doute changé des tâches : on relit.
        center.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main) {
            [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == Self.bundleID else { return }
            // Les allers-retours rapides avec ClickUp ne relisent pas à chaque fois.
            MainActor.assumeIsolated { self?.refresh(unlessWithin: Self.minimumRefreshInterval) }
        }
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tasks.removeAll(where: \.isCompleted)
                self?.refresh()
            }
        }
        if isAppRunning { startRefreshing() }
    }

    private func tokenLoaded(_ saved: String?) {
        // Un jeton saisi entre-temps garde la priorité.
        guard token == nil else { return }
        token = saved
        state = saved == nil ? .noToken : .loading
        if saved != nil, isAppRunning { refresh() }
    }

    var hasToken: Bool { token != nil }
    /// L'onglet et la colonne de l'Accueil ne s'affichent que pendant que ClickUp est ouverte.
    var isActive: Bool { isAppRunning }
    var pendingCount: Int { tasks.filter { !$0.isCompleted }.count }

    // MARK: - Jeton

    /// Enregistre le jeton (« pk_… ») et vérifie qu'il marche.
    func setToken(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Keychain.save(trimmed)
        token = trimmed
        resetAccount()
        state = .loading
        refresh()
    }

    func removeToken() {
        Keychain.delete()
        token = nil
        resetAccount()
        tasks = []
        state = .noToken
    }

    private func resetAccount() {
        lists = []
        recentTasks = []
        userID = nil
        userName = nil
        teamIDs = []
        doneStatusByList = [:]
    }

    func openTokenPage() {
        if let url = URL(string: "https://app.clickup.com/settings/apps") { NSWorkspace.shared.open(url) }
    }

    // MARK: - App

    private func setAppRunning(_ running: Bool) {
        guard running != isAppRunning else { return }
        isAppRunning = running
        if running {
            startRefreshing()
        } else {
            refreshTimer?.invalidate()
            refreshTimer = nil
            dueTimer?.invalidate()
            dueTimer = nil
            onAppQuit()
        }
    }

    private func startRefreshing() {
        refresh()
        refreshTimer?.invalidate()
        // Peu souvent : la liste est surtout relue à l'ouverture de l'encoche.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        dueTimer?.invalidate()
        dueTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkDueTasks() }
        }
    }

    func openApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/ClickUp.app"))
    }

    /// Ouvre la tâche dans l'app ClickUp (lien « clickup://t/… »).
    func open(_ task: ClickUpTask) {
        if let url = URL(string: "clickup://t/\(task.id)") { NSWorkspace.shared.open(url) }
    }

    // MARK: - Lecture

    /// L'encoche s'ouvre : on relit, sauf si c'est tout frais.
    func notchOpened() {
        refresh(unlessWithin: Self.minimumRefreshInterval)
    }

    /// Relit mes tâches ; avec `interval`, seulement si la dernière relecture est plus ancienne.
    func refresh(unlessWithin interval: TimeInterval = 0) {
        guard isAppRunning, token != nil, !refreshing else { return }
        guard Self.shouldRefresh(lastRefresh: lastRefresh, now: Date(), minimumInterval: interval) else { return }
        lastRefresh = Date()
        refreshing = true
        Task {
            defer { refreshing = false }
            do {
                try await loadAccountIfNeeded()
                var list: [ClickUpTask] = []
                var recent: [ClickUpTask] = []
                for team in teamIDs {
                    list += try await fetchTasks(team: team)
                    recent += try await fetchRecentTasks(team: team)
                }
                apply(list)
                let mostRecent = Self.mostRecent(recent)
                if mostRecent != recentTasks { recentTasks = mostRecent }
                state = .ready
            } catch ClickUpError.unauthorized {
                state = .failed("Jeton refusé par ClickUp")
            } catch {
                // Hors ligne un instant : on garde la liste affichée.
                if tasks.isEmpty { state = .failed("ClickUp injoignable") }
                NSLog("[Encoche] ClickUp refresh failed: \(error.localizedDescription)")
            }
        }
    }

    private func loadAccountIfNeeded() async throws {
        if userID == nil {
            let json = try await request("user")
            let user = json["user"] as? [String: Any]
            userID = user?["id"] as? Int
            userName = user?["username"] as? String ?? user?["email"] as? String
        }
        if teamIDs.isEmpty {
            let json = try await request("team")
            teamIDs = (json["teams"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        }
    }

    /// Mes tâches ouvertes, triées par échéance ; on garde celles du jour, en retard ou en cours.
    private func fetchTasks(team: String) async throws -> [ClickUpTask] {
        guard let userID else { return [] }
        var result: [ClickUpTask] = []
        // Trois pages de 100 suffisent largement pour ce qui est du jour.
        for page in 0..<3 {
            let json = try await request(
                "team/\(team)/task",
                query: [
                    URLQueryItem(name: "assignees[]", value: String(userID)),
                    URLQueryItem(name: "subtasks", value: "true"),
                    URLQueryItem(name: "include_closed", value: "false"),
                    URLQueryItem(name: "order_by", value: "due_date"),
                    URLQueryItem(name: "reverse", value: "true"),
                    URLQueryItem(name: "page", value: String(page)),
                ])
            let tasks = json["tasks"] as? [[String: Any]] ?? []
            result += tasks.compactMap(Self.makeTask)
            if tasks.count < 100 || json["last_page"] as? Bool == true { break }
        }
        return result
    }

    /// Mes tâches modifiées ces 7 derniers jours (terminées comprises), plus récentes d'abord.
    private func fetchRecentTasks(team: String) async throws -> [ClickUpTask] {
        guard let userID else { return [] }
        let since = Int64(Date().addingTimeInterval(-7 * 86_400).timeIntervalSince1970 * 1000)
        let json = try await request(
            "team/\(team)/task",
            query: [
                URLQueryItem(name: "assignees[]", value: String(userID)),
                URLQueryItem(name: "subtasks", value: "true"),
                URLQueryItem(name: "include_closed", value: "true"),
                URLQueryItem(name: "order_by", value: "updated"),
                URLQueryItem(name: "date_updated_gt", value: String(since)),
                URLQueryItem(name: "page", value: "0"),
            ])
        return (json["tasks"] as? [[String: Any]] ?? []).compactMap(Self.makeTask)
    }

    nonisolated static func shouldRefresh(lastRefresh: Date?, now: Date, minimumInterval: TimeInterval) -> Bool {
        guard let lastRefresh else { return true }
        return now.timeIntervalSince(lastRefresh) >= minimumInterval
    }

    // MARK: - Statuts « en cours »

    func isActiveStatus(_ status: ClickUpStatus) -> Bool {
        activeStatuses?.contains(status.id) ?? true
    }

    /// Coche ou décoche un statut ; le premier choix part de tous les statuts cochés.
    func toggleActiveStatus(_ status: ClickUpStatus) {
        var active = activeStatuses ?? Set(customStatuses.map(\.id))
        if active.contains(status.id) { active.remove(status.id) } else { active.insert(status.id) }
        activeStatuses = active
        apply(openTasks)
    }

    /// Revient à tous les statuts intermédiaires.
    func resetActiveStatuses() {
        activeStatuses = nil
        apply(openTasks)
    }

    /// Les statuts intermédiaires distincts, les plus fréquents d'abord.
    nonisolated static func customStatuses(in tasks: [ClickUpTask]) -> [ClickUpStatus] {
        var counts: [String: (status: ClickUpStatus, count: Int)] = [:]
        for task in tasks where task.isInProgress && !task.status.isEmpty {
            let status = ClickUpStatus(name: task.status, color: task.statusColor)
            counts[status.id, default: (status, 0)].count += 1
        }
        return counts.values
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.status.name < $1.status.name }
            .map(\.status)
    }

    nonisolated static func mostRecent(_ tasks: [ClickUpTask], limit: Int = 20) -> [ClickUpTask] {
        Array(tasks.sorted { ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast) }.prefix(limit))
    }

    /// Garde mes tâches ouvertes et en tire celles du jour, en retard ou en cours.
    private func apply(_ all: [ClickUpTask]) {
        openTasks = all
        let statuses = Self.customStatuses(in: all)
        if statuses != customStatuses { customStatuses = statuses }
        let now = Date()
        let list = all.filter { Self.isRelevant($0, now: now, activeStatuses: activeStatuses) }
        // Les tâches cochées depuis l'encoche restent visibles, barrées.
        let checked = tasks.filter { old in old.isCompleted && !list.contains { $0.id == old.id } }
        let today = Calendar.current.startOfDay(for: Date())
        let merged = (list + checked).sorted { Self.order($0, $1, today: today) }
        if merged != tasks { tasks = merged }
        checkDueTasks()
    }

    // MARK: - Création

    private static func savedTargetList() -> ClickUpList? {
        UserDefaults.standard.data(forKey: "clickUpTargetList").flatMap { try? JSONDecoder().decode(ClickUpList.self, from: $0) }
    }

    /// Charge les listes de tous mes espaces (une fois par session).
    func loadListsIfNeeded() {
        guard lists.isEmpty, token != nil else { return }
        Task {
            do {
                try await loadAccountIfNeeded()
                var found: [ClickUpList] = []
                for team in teamIDs { found += try await fetchLists(team: team) }
                lists = found
                // Liste choisie supprimée depuis : on l'oublie.
                if let target = targetList, !found.isEmpty, !found.contains(where: { $0.id == target.id }) {
                    targetList = nil
                }
            } catch {
                NSLog("[Encoche] ClickUp lists failed: \(error.localizedDescription)")
            }
        }
    }

    private func fetchLists(team: String) async throws -> [ClickUpList] {
        let archived = [URLQueryItem(name: "archived", value: "false")]
        let spaces = try await request("team/\(team)/space", query: archived)["spaces"] as? [[String: Any]] ?? []
        var result: [ClickUpList] = []
        for space in spaces {
            guard let spaceID = space["id"] as? String else { continue }
            let spaceName = space["name"] as? String ?? ""
            let folderless = try await request("space/\(spaceID)/list", query: archived)["lists"] as? [[String: Any]] ?? []
            result += Self.makeLists(folderless, path: spaceName)
            let folders = try await request("space/\(spaceID)/folder", query: archived)["folders"] as? [[String: Any]] ?? []
            for folder in folders {
                let path = [spaceName, folder["name"] as? String ?? ""].filter { !$0.isEmpty }.joined(separator: " › ")
                result += Self.makeLists(folder["lists"] as? [[String: Any]] ?? [], path: path)
            }
        }
        return result
    }

    nonisolated static func makeLists(_ json: [[String: Any]], path: String) -> [ClickUpList] {
        json.compactMap { list in
            guard let id = list["id"] as? String, let name = list["name"] as? String else { return nil }
            return ClickUpList(id: id, name: name, path: path)
        }
    }

    /// Crée une tâche pour aujourd'hui, assignée à moi, dans la liste choisie.
    /// Rend `false` si elle n'a pas pu être créée (le texte reste alors dans le champ).
    func createTask(named name: String) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let list = targetList, !isCreating else { return false }
        isCreating = true
        defer { isCreating = false }
        do {
            try await loadAccountIfNeeded()
            var body: [String: Any] = [
                "name": name,
                "due_date": Self.todayDueDate(),
                "due_date_time": false,
            ]
            if let userID { body["assignees"] = [userID] }
            let json = try await request("list/\(list.id)/task", method: "POST", body: body)
            if let task = Self.makeTask(json) {
                let today = Calendar.current.startOfDay(for: Date())
                tasks = (tasks.filter { $0.id != task.id } + [task]).sorted { Self.order($0, $1, today: today) }
            }
            return true
        } catch {
            NSLog("[Encoche] ClickUp task creation failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Aujourd'hui à midi (en millisecondes) : la même journée quel que soit le fuseau de l'équipe.
    nonisolated static func todayDueDate(now: Date = Date()) -> Int64 {
        let noon = dueDate(for: .today, now: now) ?? now
        return Int64(noon.timeIntervalSince1970 * 1000)
    }

    // MARK: - Rappels d'échéance

    /// Prévient quelques minutes avant l'heure d'une tâche.
    nonisolated static let dueAlertLead: TimeInterval = 5 * 60

    private func checkDueTasks() {
        guard dueAlertsEnabled(), let alerts else { return }
        for task in Self.tasksDueSoon(tasks, now: Date(), alreadyAlerted: alertedKeys) {
            alertedKeys.insert(Self.alertKey(task))
            postDueAlert(task, alerts: alerts)
        }
    }

    nonisolated static func alertKey(_ task: ClickUpTask) -> String {
        "\(task.id)-\(task.due?.timeIntervalSince1970 ?? 0)"
    }

    /// Tâches à l'heure dans moins de 5 minutes (ou tout juste passée), pas encore rappelées.
    nonisolated static func tasksDueSoon(_ tasks: [ClickUpTask], now: Date, alreadyAlerted: Set<String>)
        -> [ClickUpTask]
    {
        tasks.filter { task in
            guard task.hasTime, !task.isCompleted, let due = task.due else { return false }
            let remaining = due.timeIntervalSince(now)
            return remaining <= dueAlertLead && remaining > -60 && !alreadyAlerted.contains(alertKey(task))
        }
    }

    private func postDueAlert(_ task: ClickUpTask, alerts: AlertCenter) {
        let minutes = Int(((task.due?.timeIntervalSinceNow ?? 0) / 60).rounded())
        let when = minutes > 0 ? "Échéance dans \(minutes) min" : "Échéance maintenant"
        var alert = NotchAlert(
            icon: .app(bundleID: Self.bundleID),
            source: "ClickUp",
            title: task.name,
            body: [when, task.listName].filter { !$0.isEmpty }.joined(separator: " · "),
            action: .run { [weak self] in self?.open(task) }
        )
        alert.buttons = [
            .init(label: "Ouvrir", role: .normal) { [weak self] in self?.open(task) },
            .init(label: "Terminée", role: .primary) { [weak self] in
                guard let self, let current = self.tasks.first(where: { $0.id == task.id }), !current.isCompleted
                else { return }
                self.toggle(current)
            },
        ]
        alerts.post(alert)
    }

    // MARK: - Coche

    /// Passe la tâche au statut « terminé » de sa liste (ou lui rend son statut d'avant).
    func toggle(_ task: ClickUpTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let completing = !task.isCompleted
        tasks[index].isCompleted = completing
        if completing { tasks[index].statusBeforeCompletion = task.status }
        Task {
            do {
                let status: String
                if completing {
                    status = try await doneStatus(list: task.listID)
                } else {
                    status = task.statusBeforeCompletion ?? task.status
                }
                _ = try await request("task/\(task.id)", method: "PUT", body: ["status": status])
            } catch {
                NSLog("[Encoche] ClickUp status update failed: \(error.localizedDescription)")
                if let index = tasks.firstIndex(where: { $0.id == task.id }) { tasks[index].isCompleted = !completing }
            }
        }
    }

    // MARK: - Report

    /// Change l'échéance (pour la journée, sans heure) ; la tâche quitte la liste si elle n'est
    /// plus du jour. Rétablie si ClickUp refuse.
    func postpone(_ task: ClickUpTask, to postponement: Postponement) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let now = Date()
        let newDue = Self.dueDate(for: postponement, now: now)
        var moved = task
        moved.due = newDue
        moved.hasTime = false
        let today = Calendar.current.startOfDay(for: now)
        if let open = openTasks.firstIndex(where: { $0.id == task.id }) { openTasks[open] = moved }
        if Self.isRelevant(moved, now: now, activeStatuses: activeStatuses) {
            tasks[index] = moved
            tasks.sort { Self.order($0, $1, today: today) }
        } else {
            tasks.remove(at: index)
        }
        let dueValue: Any = newDue.map { Int64($0.timeIntervalSince1970 * 1000) } ?? NSNull()
        Task {
            do {
                _ = try await request(
                    "task/\(task.id)", method: "PUT", body: ["due_date": dueValue, "due_date_time": false])
            } catch {
                NSLog("[Encoche] ClickUp postpone failed: \(error.localizedDescription)")
                tasks = (tasks.filter { $0.id != task.id } + [task]).sorted { Self.order($0, $1, today: today) }
            }
        }
    }

    /// Midi du jour visé (la même journée quel que soit le fuseau de l'équipe) ; `nil` sans échéance.
    nonisolated static func dueDate(for postponement: Postponement, now: Date) -> Date? {
        let calendar = Calendar.current
        let day: Date?
        switch postponement {
        case .today: day = now
        case .tomorrow: day = calendar.date(byAdding: .day, value: 1, to: now)
        case .nextMonday:
            day = calendar.nextDate(
                after: now, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)
        case .none: return nil
        }
        return day.flatMap { calendar.date(bySettingHour: 12, minute: 0, second: 0, of: $0) }
    }

    /// Les tâches d'un jour passé d'un côté, celles du jour et en cours de l'autre.
    nonisolated static func split(_ tasks: [ClickUpTask], now: Date) -> (late: [ClickUpTask], current: [ClickUpTask]) {
        (tasks.filter { $0.isLate(now: now) }, tasks.filter { !$0.isLate(now: now) })
    }

    private func doneStatus(list: String) async throws -> String {
        if let status = doneStatusByList[list] { return status }
        let json = try await request("list/\(list)")
        let statuses = json["statuses"] as? [[String: Any]] ?? []
        guard let status = Self.doneStatus(in: statuses) else { throw ClickUpError.noDoneStatus }
        doneStatusByList[list] = status
        return status
    }

    // MARK: - API

    private func request(
        _ path: String, method: String = "GET", query: [URLQueryItem] = [], body: [String: Any]? = nil
    ) async throws -> [String: Any] {
        guard let token, var components = URLComponents(string: "https://api.clickup.com/api/v2/\(path)") else {
            throw ClickUpError.unauthorized
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue(token, forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw ClickUpError.unauthorized }
        guard (200..<300).contains(code) else { throw URLError(.badServerResponse) }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    // MARK: - Logique (testée)

    nonisolated static func makeTask(_ json: [String: Any]) -> ClickUpTask? {
        guard let id = json["id"] as? String, let name = json["name"] as? String else { return nil }
        let status = json["status"] as? [String: Any]
        let list = json["list"] as? [String: Any]
        let priority = (json["priority"] as? [String: Any])?["id"] as? String
        func date(_ key: String) -> Date? {
            (json[key] as? String).flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1000) }
        }
        return ClickUpTask(
            id: id,
            name: name.isEmpty ? "Sans titre" : name,
            status: status?["status"] as? String ?? "",
            statusType: status?["type"] as? String ?? "open",
            statusColor: Color(hex: status?["color"] as? String) ?? .gray,
            due: date("due_date"),
            hasTime: json["due_date_time"] as? Bool ?? false,
            priority: priority.flatMap(Int.init),
            listID: list?["id"] as? String ?? "",
            listName: list?["name"] as? String ?? "",
            updated: date("date_updated")
        )
    }

    /// Du jour, en retard, ou en cours : sans échéance, un statut intermédiaire choisi
    /// (tous sans choix).
    nonisolated static func isRelevant(_ task: ClickUpTask, now: Date, activeStatuses: Set<String>? = nil) -> Bool {
        if task.statusType == "done" || task.statusType == "closed" { return false }
        if let due = task.due,
            let dayEnd = Calendar.current.date(
                byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)), due < dayEnd
        {
            return true
        }
        guard task.isInProgress else { return false }
        return activeStatuses?.contains(task.status.lowercased()) ?? true
    }

    /// Le statut « terminé » d'une liste : de type « closed », sinon « done ».
    nonisolated static func doneStatus(in statuses: [[String: Any]]) -> String? {
        for type in ["closed", "done"] {
            if let status = statuses.first(where: { $0["type"] as? String == type })?["status"] as? String {
                return status
            }
        }
        return nil
    }

    /// En retard d'abord, puis la journée (sans heure, puis par heure), puis en cours sans échéance ;
    /// à égalité, la plus prioritaire.
    nonisolated static func order(
        _ a: ClickUpTask, _ b: ClickUpTask,
        today: Date = Calendar.current.startOfDay(for: Date())
    ) -> Bool {
        func rank(_ task: ClickUpTask) -> Int {
            guard let due = task.due else { return 3 }
            if due < today { return 0 }
            return task.hasTime ? 2 : 1
        }
        let (ra, rb) = (rank(a), rank(b))
        if ra != rb { return ra < rb }
        if let da = a.due, let db = b.due, da != db { return da < db }
        return (a.priority ?? 5) < (b.priority ?? 5)
    }
}

enum ClickUpError: Error { case unauthorized, noDoneStatus }

extension Color {
    /// Couleur « #rrggbb » (celle des statuts ClickUp).
    init?(hex: String?) {
        guard var hex else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// Le jeton ClickUp, dans le Trousseau de session.
private enum Keychain {
    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.guillaumeprost.notch.clickup",
            kSecAttrAccount as String: "api-token",
        ]
    }

    static func read() -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) {
        delete()
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess { NSLog("[Encoche] ClickUp token save failed: \(status)") }
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
