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
        .foregroundStyle(.primary)
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
                .foregroundStyle(.primary.opacity(0.45))
            Text(day.formatted(.dateTime.day()))
                .font(.system(size: 13, weight: isSelected || isToday ? .bold : .medium).monospacedDigit())
                .foregroundStyle(numberColor)
                .frame(width: 24, height: 24)
                .background {
                    if isSelected {
                        Circle().fill(isToday ? Color.red : Color.primary)
                    } else if hovering {
                        Circle().fill(.primary.opacity(0.12))
                    }
                }
            Circle()
                .fill(.primary.opacity(isBusy ? 0.5 : 0))
                .frame(width: 3, height: 3)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var numberColor: Color {
        // Sélectionné : texte en couleur de fond sur une pastille de la couleur du texte.
        if isSelected { return isToday ? .white : Color(nsColor: .windowBackgroundColor) }
        return isToday ? .red : .primary
    }
}

// MARK: - Liste des événements du jour

private struct Agenda: View {
    @Environment(CalendarController.self) private var calendar

    var body: some View {
        if calendar.events.isEmpty {
            Text("Aucun événement")
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.45))
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
                    .foregroundStyle(isNow ? event.color : .primary.opacity(0.5))
            }
            Spacer(minLength: 0)
            if let url = event.meetingURL, !isPast {
                Button { NSWorkspace.shared.open(url) } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 20)
                        .background(Capsule().fill(Color.green.opacity(isNow ? 1 : 0.7)))
                }
                .buttonStyle(.plain)
                .help("Rejoindre la réunion")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isNow ? event.color.opacity(0.18) : .primary.opacity(hovering ? 0.08 : 0))
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
                .foregroundStyle(.primary.opacity(0.6))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.6))
            Button(button, action: action)
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Onglet Calendrier

/// Onglet Calendrier : le mois à gauche, l'agenda du jour choisi à droite.
struct CalendarTab: View {
    @Environment(CalendarController.self) private var calendar

    var body: some View {
        switch calendar.access {
        case .granted:
            HStack(spacing: 20) {
                MonthGrid()
                    .frame(width: 196)
                Rectangle()
                    .fill(.primary.opacity(0.12))
                    .frame(width: 1)
                    .padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 6) {
                    DayHeader()
                    Agenda()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .foregroundStyle(.primary)
        case .notDetermined:
            AccessPrompt(message: "Affiche ton agenda ici", button: "Autoriser le calendrier", action: calendar.requestAccess)
        case .denied:
            AccessPrompt(message: "Accès au calendrier refusé", button: "Ouvrir les Réglages", action: calendar.openPrivacySettings)
        }
    }
}

private struct DayHeader: View {
    @Environment(CalendarController.self) private var calendar

    var body: some View {
        let isToday = Calendar.current.isDateInToday(calendar.selectedDay)
        HStack(spacing: 6) {
            Text(calendar.selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalizedFirst)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
            if isToday {
                Text("Aujourd'hui")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.red)
            }
            Spacer(minLength: 0)
            if !isToday {
                Button { calendar.selectToday() } label: {
                    Text("Aujourd'hui")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .frame(height: 18)
                        .background(Capsule().fill(.primary.opacity(0.1)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.6))
                    .frame(width: 20, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ouvrir Calendrier")
        }
        .animation(.snappy, value: isToday)
    }
}

/// Mini-calendrier du mois : un point sous les jours qui ont des événements.
private struct MonthGrid: View {
    @Environment(CalendarController.self) private var calendar
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Text(calendar.displayedMonth.formatted(.dateTime.month(.wide).year()).capitalizedFirst)
                    .font(.system(size: 12, weight: .bold))
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                arrow("chevron.left") { calendar.showMonth(offset: -1) }
                arrow("chevron.right") { calendar.showMonth(offset: 1) }
            }
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.4))
                        .frame(height: 10)
                }
                ForEach(calendar.monthGridDays, id: \.self) { day in
                    MonthDayCell(
                        day: day,
                        inMonth: Calendar.current.isDate(day, equalTo: calendar.displayedMonth, toGranularity: .month),
                        isSelected: Calendar.current.isDate(day, inSameDayAs: calendar.selectedDay),
                        isToday: Calendar.current.isDateInToday(day),
                        isBusy: calendar.busyDays.contains(day)
                    )
                    .onTapGesture { calendar.select(day) }
                }
            }
        }
        .animation(.snappy(duration: 0.2), value: calendar.displayedMonth)
    }

    /// Initiales des jours, dans l'ordre de la semaine du Mac (lundi en premier en France).
    private var weekdaySymbols: [String] {
        let cal = Calendar.current
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[(cal.firstWeekday - 1 + $0) % 7].uppercased() }
    }

    private func arrow(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.primary.opacity(0.6))
                .frame(width: 18, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct MonthDayCell: View {
    let day: Date
    let inMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let isBusy: Bool
    @State private var hovering = false

    var body: some View {
        ZStack {
            if isSelected {
                Circle().fill(isToday ? Color.red : Color.primary.opacity(0.85))
                    .frame(width: 13, height: 13)
            } else if hovering {
                Circle().fill(.primary.opacity(0.12)).frame(width: 13, height: 13)
            }
            Text(day.formatted(.dateTime.day()))
                .font(.system(size: 9, weight: isToday || isSelected ? .bold : .medium).monospacedDigit())
                .foregroundStyle(numberColor)
        }
        .frame(height: 13)
        .overlay(alignment: .bottom) {
            if isBusy && !isSelected {
                Circle()
                    .fill(isToday ? Color.red : .primary.opacity(inMonth ? 0.55 : 0.25))
                    .frame(width: 2.5, height: 2.5)
                    .offset(y: 2.5)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var numberColor: Color {
        if isSelected { return isToday ? .white : Color(nsColor: .windowBackgroundColor) }
        if isToday { return .red }
        return .primary.opacity(inMonth ? 0.9 : 0.3)
    }
}

private extension String {
    /// Majuscule à la première lettre seulement (« Jeudi 5 novembre »).
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
