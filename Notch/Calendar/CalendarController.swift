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
    /// Lien de visio trouvé dans l'événement (Meet, Zoom, Teams…).
    var meetingURL: URL?
}

/// Trouve un lien de visio dans un événement : son URL, son lieu ou ses notes.
enum MeetingLink {
    private static let hosts = [
        "meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com",
        "webex.com", "whereby.com", "facetime.apple.com",
    ]
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func find(in event: EKEvent) -> URL? {
        if let url = event.url, isMeeting(url) { return url }
        for text in [event.location, event.notes].compactMap({ $0 }) {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector?.matches(in: text, range: range) ?? [] {
                if let url = match.url, isMeeting(url) { return url }
            }
        }
        return nil
    }

    private static func isMeeting(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
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
    /// Prochaine réunion qui commence dans moins de 10 minutes (activité en direct).
    private(set) var upcomingMeeting: CalendarEvent?
    static let countdownWindow: TimeInterval = 10 * 60

    /// Premier jour du mois affiché dans l'onglet Calendrier.
    private(set) var displayedMonth: Date

    /// Base EventKit partagée avec les rappels.
    private let store: EKEventStore
    /// Pour les rappels de réunion dans l'encoche.
    @ObservationIgnored var alerts: AlertCenter?
    @ObservationIgnored private var remindedIDs: Set<String> = []
    @ObservationIgnored private var reminderTimer: Timer?
    @ObservationIgnored private var countdownEnd: Task<Void, Never>?
    private let calendar = Calendar.current

    init(store: EKEventStore) {
        self.store = store
        selectedDay = Calendar.current.startOfDay(for: Date())
        displayedMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
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

    /// Grille du mois affiché : 6 semaines complètes, à partir du premier jour de la semaine.
    var monthGridDays: [Date] {
        let weekday = calendar.component(.weekday, from: displayedMonth)
        let offset = (weekday - calendar.firstWeekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -offset, to: displayedMonth) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    func showMonth(offset: Int) {
        guard let month = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        displayedMonth = month
        reload()
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
        // Jour d'un autre mois (cliqué en bordure de grille) : on y passe.
        if !calendar.isDate(selectedDay, equalTo: displayedMonth, toGranularity: .month) {
            displayedMonth = calendar.dateInterval(of: .month, for: selectedDay)?.start ?? displayedMonth
        }
        reload()
    }

    func selectToday() { select(Date()) }

    // MARK: - Rappels de réunion

    /// Vérifie toutes les 20 s s'il faut prévenir d'un événement qui commence dans la minute.
    func startMeetingReminders() {
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkUpcomingMeetings() }
        }
        checkUpcomingMeetings()
    }

    private func checkUpcomingMeetings() {
        guard access == .granted else { return }
        let now = Date()
        updateUpcomingMeeting(now: now)
        // Commence dans la minute (ou vient de commencer, si l'app était occupée).
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-60), end: now.addingTimeInterval(75), calendars: nil
        )
        for event in store.events(matching: predicate) where !event.isAllDay {
            let start = event.startDate.timeIntervalSince(now)
            guard start <= 70, start > -60 else { continue }
            let key = "\(event.calendarItemIdentifier)-\(event.startDate.timeIntervalSince1970)"
            guard !remindedIDs.contains(key) else { continue }
            remindedIDs.insert(key)
            postReminder(for: event, startsIn: start)
        }
    }

    /// Événement (avec horaire) qui commence dans les 10 prochaines minutes.
    private func updateUpcomingMeeting(now: Date) {
        let predicate = store.predicateForEvents(
            withStart: now, end: now.addingTimeInterval(Self.countdownWindow), calendars: nil
        )
        let next = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.startDate > now && $0.startDate <= now.addingTimeInterval(Self.countdownWindow) }
            .min { $0.startDate < $1.startDate }
        let meeting = next.map(Self.makeEvent)
        if meeting?.id != upcomingMeeting?.id { upcomingMeeting = meeting }
        // Le compte à rebours s'arrête au début de la réunion.
        if let start = meeting?.start {
            countdownEnd?.cancel()
            countdownEnd = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(start.timeIntervalSinceNow, 0) + 1))
                guard !Task.isCancelled, let self else { return }
                self.updateUpcomingMeeting(now: Date())
            }
        }
    }

    private func postReminder(for event: EKEvent, startsIn seconds: TimeInterval) {
        let title = event.title?.isEmpty == false ? event.title! : "Événement"
        let when = seconds > 5 ? "Commence dans 1 min" : "Commence maintenant"
        let itemID = event.calendarItemIdentifier
        let openEvent: NotchAlert.Action = .openURL(URL(string: "ical://ekevent/\(itemID)?method=show&options=more")!)

        var alert = NotchAlert(
            icon: .symbol("calendar", .red),
            source: "Calendrier",
            title: title,
            body: [when, event.location].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
            action: openEvent
        )
        if let url = MeetingLink.find(in: event) {
            // Avec un lien de visio : la notification attend une réponse.
            alert.buttons = [
                .init(label: "Ignorer", role: .normal) {},
                .init(label: "Rejoindre", role: .primary) { NSWorkspace.shared.open(url) },
            ]
        }
        alerts?.post(alert)
    }

    func open(_ event: CalendarEvent) {
        if let url = URL(string: "ical://ekevent/\(event.itemID)?method=show&options=more") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func makeEvent(_ event: EKEvent) -> CalendarEvent {
        CalendarEvent(
            id: "\(event.eventIdentifier ?? UUID().uuidString)-\(event.startDate.timeIntervalSince1970)",
            itemID: event.calendarItemIdentifier,
            title: event.title?.isEmpty == false ? event.title : "Sans titre",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            color: Color(nsColor: event.calendar.color ?? .systemBlue),
            meetingURL: MeetingLink.find(in: event)
        )
    }

    // MARK: - Chargement

    func reload() {
        guard access == .granted, let dayEnd = calendar.date(byAdding: .day, value: 1, to: selectedDay) else {
            events = []
            return
        }
        let all = store.events(matching: store.predicateForEvents(withStart: selectedDay, end: dayEnd, calendars: nil))

        events =
            all
            .filter { $0.startDate < dayEnd && $0.endDate > selectedDay }
            .sorted { a, b in
                if a.isAllDay != b.isAllDay { return a.isAllDay }
                return a.startDate < b.startDate
            }
            .map(Self.makeEvent)
    }
}
