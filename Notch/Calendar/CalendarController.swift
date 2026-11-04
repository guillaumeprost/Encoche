import AppKit
import EventKit
import Observation
import SwiftUI

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let itemID: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
}

/// Lit les événements des calendriers du Mac (iCloud, Google, Exchange… tout ce que
/// l'app Calendrier connaît) via EventKit, et se met à jour quand ils changent.
@Observable
@MainActor
final class CalendarController {
    enum Access { case notDetermined, granted, denied }

    /// Nombre de jours affichés dans le bandeau, à partir d'hier.
    static let stripLength = 7

    private(set) var access: Access
    private(set) var selectedDay: Date
    private(set) var events: [CalendarEvent] = []
    /// Jours (début de journée) qui ont au moins un événement, pour les points du bandeau.
    private(set) var busyDays: Set<Date> = []

    private let store = EKEventStore()
    private let calendar = Calendar.current

    init() {
        selectedDay = Calendar.current.startOfDay(for: Date())
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .granted
        case .notDetermined: access = .notDetermined
        default: access = .denied
        }

        let center = NotificationCenter.default
        center.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.selectToday() }
        }

        reload()
    }

    var stripDays: [Date] {
        let today = calendar.startOfDay(for: Date())
        return (-1..<(Self.stripLength - 1)).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    // MARK: - Actions

    func requestAccess() {
        Task {
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            access = granted ? .granted : .denied
            reload()
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func select(_ day: Date) {
        selectedDay = calendar.startOfDay(for: day)
        reload()
    }

    func selectToday() { select(Date()) }

    func open(_ event: CalendarEvent) {
        if let url = URL(string: "ical://ekevent/\(event.itemID)?method=show&options=more") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Chargement

    func reload() {
        guard access == .granted, let first = stripDays.first,
              let stripEnd = calendar.date(byAdding: .day, value: Self.stripLength, to: first)
        else {
            events = []
            busyDays = []
            return
        }

        let predicate = store.predicateForEvents(withStart: first, end: stripEnd, calendars: nil)
        let all = store.events(matching: predicate)

        var busy = Set<Date>()
        for event in all {
            var day = calendar.startOfDay(for: max(event.startDate, first))
            // Un événement sur plusieurs jours marque chacun de ses jours ; la fin est exclusive.
            while day < min(event.endDate, stripEnd) {
                busy.insert(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        busyDays = busy

        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: selectedDay) else { return }
        events = all
            .filter { $0.startDate < dayEnd && $0.endDate > selectedDay }
            .sorted { a, b in
                if a.isAllDay != b.isAllDay { return a.isAllDay }
                return a.startDate < b.startDate
            }
            .map { event in
                CalendarEvent(
                    id: "\(event.eventIdentifier ?? UUID().uuidString)-\(event.startDate.timeIntervalSince1970)",
                    itemID: event.calendarItemIdentifier,
                    title: event.title?.isEmpty == false ? event.title : "Sans titre",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    color: Color(nsColor: event.calendar.color ?? .systemBlue)
                )
            }
    }
}
