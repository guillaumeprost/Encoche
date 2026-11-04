import SwiftUI

struct CalendarView: View {
    @Environment(CalendarController.self) private var calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch calendar.access {
            case .granted:
                WeekStrip()
                Agenda()
            case .notDetermined:
                AccessPrompt(
                    message: "Affiche ton agenda ici",
                    button: "Autoriser le calendrier",
                    action: calendar.requestAccess
                )
            case .denied:
                AccessPrompt(
                    message: "Accès au calendrier refusé",
                    button: "Ouvrir les Réglages",
                    action: calendar.openPrivacySettings
                )
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Bandeau de la semaine

private struct WeekStrip: View {
    @Environment(CalendarController.self) private var calendar

    var body: some View {
        HStack(spacing: 2) {
            ForEach(calendar.stripDays, id: \.self) { day in
                DayCell(
                    day: day,
                    isSelected: Calendar.current.isDate(day, inSameDayAs: calendar.selectedDay),
                    isToday: Calendar.current.isDateInToday(day),
                    isBusy: calendar.busyDays.contains(day)
                )
                .onTapGesture { calendar.select(day) }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: calendar.selectedDay)
    }
}

private struct DayCell: View {
    let day: Date
    let isSelected: Bool
    let isToday: Bool
    let isBusy: Bool
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 2) {
            Text(day.formatted(.dateTime.weekday(.narrow)).uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            Text(day.formatted(.dateTime.day()))
                .font(.system(size: 13, weight: isSelected || isToday ? .bold : .medium).monospacedDigit())
                .foregroundStyle(numberColor)
                .frame(width: 24, height: 24)
                .background {
                    if isSelected {
                        Circle().fill(isToday ? .red : .white)
                    } else if hovering {
                        Circle().fill(.white.opacity(0.12))
                    }
                }
            Circle()
                .fill(.white.opacity(isBusy ? 0.5 : 0))
                .frame(width: 3, height: 3)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var numberColor: Color {
        if isSelected { return isToday ? .white : .black }
        return isToday ? .red : .white
    }
}

// MARK: - Liste des événements du jour

private struct Agenda: View {
    @Environment(CalendarController.self) private var calendar

    var body: some View {
        if calendar.events.isEmpty {
            Text("Aucun événement")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TimelineView(.everyMinute) { context in
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(spacing: 4) {
                            ForEach(calendar.events) { event in
                                EventRow(event: event, now: context.date)
                                    .id(event.id)
                                    .onTapGesture { calendar.open(event) }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                    .onAppear { scrollToNext(proxy, now: context.date) }
                    .onChange(of: calendar.events) { scrollToNext(proxy, now: context.date) }
                }
            }
        }
    }

    /// Fait défiler jusqu'au premier événement pas encore terminé.
    private func scrollToNext(_ proxy: ScrollViewProxy, now: Date) {
        guard let next = calendar.events.first(where: { !$0.isAllDay && $0.end > now }) else { return }
        proxy.scrollTo(next.id, anchor: .top)
    }
}

private struct EventRow: View {
    let event: CalendarEvent
    let now: Date
    @State private var hovering = false

    private var isPast: Bool { !event.isAllDay && event.end <= now }
    private var isNow: Bool { !event.isAllDay && event.start <= now && now < event.end }

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(event.color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(timeLabel)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(isNow ? event.color : .white.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isNow ? event.color.opacity(0.18) : .white.opacity(hovering ? 0.08 : 0))
        )
        .opacity(isPast ? 0.45 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var timeLabel: String {
        if event.isAllDay { return "Toute la journée" }
        if isNow {
            let minutes = Int(event.end.timeIntervalSince(now) / 60) + 1
            return "En cours · encore \(minutes) min"
        }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        let end = event.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }
}

// MARK: - Permission

private struct AccessPrompt: View {
    let message: String
    let button: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.6))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
            Button(button, action: action)
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
