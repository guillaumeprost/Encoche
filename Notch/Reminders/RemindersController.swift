import AppKit
import EventKit
import Observation
import SwiftUI

/// Rappel (app Rappels) à faire aujourd'hui, ou en retard.
struct TodayReminder: Identifiable, Equatable {
    let id: String
    let title: String
    /// Échéance ; sans heure quand le rappel est pour la journée.
    let due: Date?
    let hasTime: Bool
    let list: String
    let color: Color
    var isCompleted = false

    /// En retard : un jour passé, ou une heure passée aujourd'hui.
    func isOverdue(now: Date) -> Bool {
        guard let due, !isCompleted else { return false }
        return hasTime ? due < now : due < Calendar.current.startOfDay(for: now)
    }
}

/// Lit les rappels du jour (et ceux en retard) via EventKit, et les coche.
@Observable
@MainActor
final class RemindersController {
    enum Access { case notDetermined, granted, denied }

    private(set) var access: Access
    private(set) var reminders: [TodayReminder] = []

    /// Base EventKit partagée avec le calendrier.
    private let store: EKEventStore

    init(store: EKEventStore) {
        self.store = store
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: access = .granted
        case .notDetermined: access = .notDetermined
        default: access = .denied
        }
        let center = NotificationCenter.default
        center.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // Nouveau jour : on oublie les rappels cochés la veille.
                self?.reminders.removeAll(where: \.isCompleted)
                self?.reload()
            }
        }
        reload()
    }

    /// Rappels qui restent à faire.
    var pendingCount: Int { reminders.filter { !$0.isCompleted }.count }

    func requestAccess() {
        Task {
            access = (try? await store.requestFullAccessToReminders()) == true ? .granted : .denied
            reload()
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Coche le rappel (ou le décoche) ; il reste affiché barré jusqu'au lendemain.
    func toggle(_ reminder: TodayReminder) {
        guard let item = store.calendarItem(withIdentifier: reminder.id) as? EKReminder else { return }
        item.isCompleted.toggle()
        do {
            try store.save(item, commit: true)
        } catch {
            NSLog("[Encoche] Reminder save failed: \(error.localizedDescription)")
            return
        }
        if let index = reminders.firstIndex(where: { $0.id == reminder.id }) {
            reminders[index].isCompleted = item.isCompleted
        }
    }

    func open(_ reminder: TodayReminder) {
        if let url = URL(string: "x-apple-reminderkit://REMCDReminder/\(reminder.id)") {
            NSWorkspace.shared.open(url)
        }
    }

    func openApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Reminders.app"))
    }

    func reload() {
        guard access == .granted,
            let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))
        else {
            reminders = []
            return
        }
        // Sans date de début : aussi les rappels en retard.
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: dayEnd, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] items in
            let list = (items ?? []).map(Self.makeReminder)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.apply(list) }
            }
        }
    }

    private func apply(_ list: [TodayReminder]) {
        // Les rappels cochés depuis l'encoche restent visibles, barrés.
        let checked = reminders.filter { old in old.isCompleted && !list.contains { $0.id == old.id } }
        let today = Calendar.current.startOfDay(for: Date())
        let merged = (list + checked).sorted { Self.order($0, $1, today: today) }
        if merged != reminders { reminders = merged }
    }

    nonisolated private static func makeReminder(_ item: EKReminder) -> TodayReminder {
        let components = item.dueDateComponents
        return TodayReminder(
            id: item.calendarItemIdentifier,
            title: item.title?.isEmpty == false ? item.title! : "Sans titre",
            due: components.flatMap { Calendar.current.date(from: $0) },
            hasTime: components?.hour != nil,
            list: item.calendar?.title ?? "",
            color: Color(nsColor: item.calendar?.color ?? .systemOrange)
        )
    }

    /// Les rappels en retard d'abord, puis ceux de la journée sans heure, puis par heure.
    nonisolated static func order(
        _ a: TodayReminder, _ b: TodayReminder,
        today: Date = Calendar.current.startOfDay(for: Date())
    ) -> Bool {
        let aLate = (a.due ?? today) < today
        let bLate = (b.due ?? today) < today
        if aLate != bLate { return aLate }
        if a.hasTime != b.hasTime { return !a.hasTime }
        return (a.due ?? .distantPast) < (b.due ?? .distantPast)
    }
}
