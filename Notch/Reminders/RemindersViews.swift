import SwiftUI

/// Onglet Rappels : les rappels du jour et ceux en retard, à cocher.
struct RemindersTab: View {
    @Environment(RemindersController.self) private var reminders

    var body: some View {
        switch reminders.access {
        case .granted:
            VStack(alignment: .leading, spacing: 10) {
                header
                RemindersList(large: true)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .notDetermined:
            AccessPrompt(symbol: "checklist", message: "Affiche tes rappels du jour ici", button: "Autoriser les rappels",
                                  action: reminders.requestAccess)
        case .denied:
            AccessPrompt(symbol: "checklist", message: "Accès aux rappels refusé", button: "Ouvrir les Réglages",
                                  action: reminders.openPrivacySettings)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Aujourd'hui")
                .font(.system(size: 16, weight: .bold))
            if reminders.pendingCount > 0 {
                Text("\(reminders.pendingCount) à faire")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            Button(action: reminders.openApp) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.6))
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ouvrir Rappels")
        }
        .animation(.snappy, value: reminders.pendingCount)
    }
}

/// Petite colonne de rappels sur l'Accueil.
struct RemindersColumn: View {
    @Environment(RemindersController.self) private var reminders

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Rappels")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.5))
                if reminders.pendingCount > 0 {
                    Text("\(reminders.pendingCount)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 4)
            if reminders.access == .granted {
                RemindersList(large: false)
            } else {
                let notAsked = reminders.access == .notDetermined
                Button(notAsked ? "Afficher" : "Autoriser",
                       action: notAsked ? reminders.requestAccess : reminders.openPrivacySettings)
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(.primary)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Liste des rappels, avec un message quand il n'y a rien à faire.
private struct RemindersList: View {
    @Environment(RemindersController.self) private var reminders
    let large: Bool

    var body: some View {
        if reminders.reminders.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: large ? 20 : 15))
                Text("Rien à faire")
                    .font(.system(size: large ? 12 : 11))
            }
            .foregroundStyle(.primary.opacity(0.4))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TimelineView(.everyMinute) { context in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: large ? 4 : 2) {
                        ForEach(reminders.reminders) { reminder in
                            ReminderRow(reminder: reminder, now: context.date, large: large)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            .animation(.snappy, value: reminders.reminders)
        }
    }
}

private struct ReminderRow: View {
    @Environment(RemindersController.self) private var reminders
    let reminder: TodayReminder
    let now: Date
    let large: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: large ? 9 : 6) {
            Button { reminders.toggle(reminder) } label: {
                ZStack {
                    Circle().strokeBorder(reminder.color, lineWidth: 1.5)
                    if reminder.isCompleted {
                        Circle().fill(reminder.color).padding(3)
                    }
                }
                .frame(width: large ? 17 : 14, height: large ? 17 : 14)
                .padding(2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(reminder.isCompleted ? "Marquer comme non terminé" : "Marquer comme terminé")

            VStack(alignment: .leading, spacing: 1) {
                Text(reminder.title)
                    .font(.system(size: large ? 13.5 : 11.5, weight: .medium))
                    .strikethrough(reminder.isCompleted)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.system(size: large ? 11.5 : 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(reminder.isOverdue(now: now) ? Color.red : .primary.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, large ? 4 : 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.primary.opacity(hovering ? 0.08 : 0))
        )
        .opacity(reminder.isCompleted ? 0.45 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { reminders.open(reminder) }
    }

    /// Heure, ou date pour un rappel en retard ; avec la liste dans l'onglet.
    private var detail: String? {
        var parts: [String] = []
        if let due = reminder.due {
            if !Calendar.current.isDateInToday(due) {
                parts.append("En retard · " + due.formatted(.dateTime.day().month(.abbreviated)))
            } else if reminder.hasTime {
                parts.append(due.formatted(date: .omitted, time: .shortened))
            }
        }
        if large, !reminder.list.isEmpty { parts.append(reminder.list) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
