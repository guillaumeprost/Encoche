import AppKit

/// Briefing du matin : à la première ouverture du Mac de la journée (réveil, déverrouillage ou
/// lancement d'Encoche, avant midi), Claude résume l'agenda, les tâches ClickUp et les rappels.
/// Une seule fois par jour, et seulement s'il y a quelque chose à dire.
@MainActor
final class ClaudeBriefing {
    private static let lastDayKey = "claudeBriefingLastDay"
    /// Le briefing n'a de sens que le matin.
    nonisolated static let hours = 5..<12
    /// Laisse aux agendas et à ClickUp le temps de se charger après le réveil.
    private static let delay: Duration = .seconds(20)

    private let ask: ClaudeAsk
    private let isEnabled: @MainActor () -> Bool
    private let context: @MainActor () -> ClaudePrompts.Briefing
    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?

    init(
        ask: ClaudeAsk, isEnabled: @escaping @MainActor () -> Bool,
        context: @escaping @MainActor () -> ClaudePrompts.Briefing
    ) {
        self.ask = ask
        self.isEnabled = isEnabled
        self.context = context
    }

    func start() {
        let trigger: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule() }
        }
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: trigger))
        observers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main, using: trigger))
        schedule()
    }

    /// Faut-il un briefing maintenant ? Le matin, pas encore fait aujourd'hui.
    nonisolated static func isDue(now: Date, lastDay: String?, calendar: Calendar = .current) -> Bool {
        hours.contains(calendar.component(.hour, from: now)) && lastDay != dayKey(now, calendar: calendar)
    }

    nonisolated static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    private func schedule() {
        guard pending == nil, isEnabled(),
            Self.isDue(now: Date(), lastDay: UserDefaults.standard.string(forKey: Self.lastDayKey))
        else { return }
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.delay)
            guard let self else { return }
            self.pending = nil
            self.runIfDue()
        }
    }

    private func runIfDue() {
        let now = Date()
        guard isEnabled(), Self.isDue(now: now, lastDay: UserDefaults.standard.string(forKey: Self.lastDayKey)) else { return }
        let day = context()
        UserDefaults.standard.set(Self.dayKey(now), forKey: Self.lastDayKey)
        guard !day.isEmpty else { return }
        ask.ask(ClaudePrompts.briefing(day, date: now))
    }

    /// Briefing à la demande (menu de l'onglet Claude), même déjà fait aujourd'hui.
    func runNow() {
        ask.ask(ClaudePrompts.briefing(context(), date: Date()))
    }
}
