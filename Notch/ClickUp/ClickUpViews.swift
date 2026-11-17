import SwiftUI

/// Onglet ClickUp : mes tâches du jour (à cocher), l'activité récente et mes notifications.
struct ClickUpTab: View {
    @Environment(ClickUpController.self) private var clickUp
    @Environment(AppSettings.self) private var settings
    @Environment(AlertCenter.self) private var alerts

    /// Notifications de l'app ClickUp relayées par Encoche (l'API n'expose pas la boîte de réception).
    private var notifications: [NotchAlert] {
        alerts.history.filter { alert in
            if case .app(let bundleID) = alert.icon { return bundleID == ClickUpController.bundleID }
            return false
        }
    }

    var body: some View {
        switch clickUp.state {
        case .noToken:
            AccessPrompt(
                symbol: Self.symbol, message: "Relie ClickUp pour voir tes tâches ici", button: "Ouvrir les Réglages",
                action: settings.openSettings)
        case .failed(let message) where clickUp.tasks.isEmpty:
            AccessPrompt(symbol: Self.symbol, message: message, button: "Réessayer") { clickUp.refresh() }
        default:
            VStack(alignment: .leading, spacing: 10) {
                header
                switch clickUp.section {
                case .todo:
                    ClickUpTaskList(large: true)
                    NewClickUpTaskField()
                case .activity:
                    ClickUpActivityList()
                case .notifications:
                    ClickUpNotificationList(notifications: notifications)
                }
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    static let symbol = NotchTab.clickUp.symbol

    private var header: some View {
        HStack(spacing: 6) {
            @Bindable var clickUp = clickUp
            Picker("Section", selection: $clickUp.section) {
                ForEach(ClickUpController.Section.allCases) { section in
                    Text(sectionTitle(section)).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer(minLength: 0)
            if clickUp.section == .todo, !clickUp.customStatuses.isEmpty {
                InProgressStatusesMenu()
            }
            Button(action: clickUp.openApp) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.6))
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ouvrir ClickUp")
        }
        .animation(.snappy, value: clickUp.pendingCount)
    }

    /// Avec le nombre de tâches à faire.
    private func sectionTitle(_ section: ClickUpController.Section) -> String {
        switch section {
        case .todo where clickUp.pendingCount > 0: "\(section.label) · \(clickUp.pendingCount)"
        case .notifications where !notifications.isEmpty: "\(section.label) · \(notifications.count)"
        default: section.label
        }
    }
}

/// Choix des statuts qui comptent comme « en cours » : leurs tâches sans échéance s'affichent.
private struct InProgressStatusesMenu: View {
    @Environment(ClickUpController.self) private var clickUp

    var body: some View {
        Menu {
            Section("Sans échéance, afficher les tâches en…") {
                ForEach(clickUp.customStatuses) { status in
                    Toggle(
                        isOn: Binding(
                            get: { clickUp.isActiveStatus(status) },
                            set: { _ in
                                withAnimation(.snappy) { clickUp.toggleActiveStatus(status) }
                            })
                    ) {
                        Text(status.name)
                    }
                }
            }
            if clickUp.activeStatuses != nil {
                Divider()
                Button("Tous les statuts") { withAnimation(.snappy) { clickUp.resetActiveStatuses() } }
            }
        } label: {
            Image(
                systemName: clickUp.activeStatuses == nil
                    ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
            )
            .font(.system(size: 13))
            .foregroundStyle(clickUp.activeStatuses == nil ? Color.primary.opacity(0.6) : Color.clickUp)
            .frame(width: 24, height: 22)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Statuts « en cours » (tâches sans échéance)")
    }
}

/// Mes tâches modifiées ces 7 derniers jours, la plus récente en haut.
private struct ClickUpActivityList: View {
    @Environment(ClickUpController.self) private var clickUp

    var body: some View {
        if clickUp.recentTasks.isEmpty {
            EmptyClickUpState(
                symbol: "clock.arrow.circlepath", text: "Aucune activité cette semaine", loading: clickUp.state == .loading)
        } else {
            TimelineView(.everyMinute) { context in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(clickUp.recentTasks) { task in
                            ClickUpActivityRow(task: task, now: context.date)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            .animation(.snappy, value: clickUp.recentTasks)
        }
    }
}

private struct ClickUpActivityRow: View {
    @Environment(ClickUpController.self) private var clickUp
    let task: ClickUpTask
    let now: Date
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(task.statusColor)
                .frame(width: 9, height: 9)
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(task.name)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(1)
                Text([task.status, task.listName].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let updated = task.updated {
                Text(updated, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.primary.opacity(0.45))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.primary.opacity(hovering ? 0.08 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { clickUp.open(task) }
        .help("Ouvrir dans ClickUp")
    }
}

/// Les notifications envoyées par l'app ClickUp, relayées dans l'encoche.
private struct ClickUpNotificationList: View {
    let notifications: [NotchAlert]

    var body: some View {
        if notifications.isEmpty {
            EmptyClickUpState(symbol: "bell.slash", text: "Aucune notification ClickUp", loading: false)
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 4) {
                    ForEach(notifications) { HistoryRow(alert: $0) }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

private struct EmptyClickUpState: View {
    let symbol: String
    let text: String
    let loading: Bool

    var body: some View {
        VStack(spacing: 4) {
            if loading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: symbol).font(.system(size: 20))
                Text(text).font(.system(size: 12))
            }
        }
        .foregroundStyle(.primary.opacity(0.4))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Champ pour créer une tâche pour aujourd'hui, avec le choix de la liste à gauche.
private struct NewClickUpTaskField: View {
    @Environment(ClickUpController.self) private var clickUp
    @State private var name = ""
    @State private var failed = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            listMenu
            TextField(
                clickUp.targetList == nil ? "Choisis d'abord une liste…" : "Nouvelle tâche pour aujourd'hui…",
                text: $name
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13.5))
            .focused($focused)
            .disabled(clickUp.targetList == nil)
            .onSubmit(create)
            .onExitCommand { focused = false }
            .onChange(of: name) { failed = false }

            if failed {
                Label("Non créée", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
            }
            if clickUp.isCreating {
                ProgressView().controlSize(.small)
            } else if !name.trimmingCharacters(in: .whitespaces).isEmpty, clickUp.targetList != nil {
                Button(action: create) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.clickUp)
                }
                .buttonStyle(.plain)
                .help("Créer la tâche")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(.primary.opacity(0.08)))
        .onAppear {
            clickUp.loadListsIfNeeded()
            if clickUp.wantsNewTaskFocus {
                clickUp.wantsNewTaskFocus = false
                focused = true
            }
        }
    }

    /// Les listes, rangées par espace (et dossier).
    private var listMenu: some View {
        Menu {
            if clickUp.lists.isEmpty {
                Text("Chargement des listes…")
            }
            let groups = Dictionary(grouping: clickUp.lists, by: \.path)
            ForEach(groups.keys.sorted(), id: \.self) { path in
                Section(path) {
                    ForEach(groups[path] ?? []) { list in
                        Button {
                            clickUp.targetList = list
                            focused = true
                        } label: {
                            if list.id == clickUp.targetList?.id {
                                Label(list.name, systemImage: "checkmark")
                            } else {
                                Text(list.name)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text(clickUp.targetList?.name ?? "Liste")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.clickUp)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .help("Liste où créer la tâche")
    }

    private func create() {
        let text = name
        Task {
            if await clickUp.createTask(named: text) {
                if name == text { name = "" }
            } else {
                failed = true
            }
        }
    }
}

/// Petite colonne de tâches ClickUp sur l'Accueil, sous les rappels.
struct ClickUpColumn: View {
    @Environment(ClickUpController.self) private var clickUp
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ClickUpLogo().frame(width: 12, height: 12)
                Text("ClickUp")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.7))
                let (late, current) = ClickUpController.split(clickUp.tasks.filter { !$0.isCompleted }, now: Date())
                if !current.isEmpty {
                    Text("\(current.count)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.clickUp)
                }
                if !late.isEmpty {
                    // Les retards restent dans l'onglet : un clic y mène, groupe déplié.
                    Button {
                        clickUp.section = .todo
                        clickUp.showsLateTasks = true
                        settings.tab = .clickUp
                    } label: {
                        Text("\(late.count) en retard")
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .help("Voir les tâches en retard")
                }
                Spacer(minLength: 0)
                Button {
                    clickUp.wantsNewTaskFocus = true
                    settings.tab = .clickUp
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.5))
                        .frame(width: 18, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Nouvelle tâche ClickUp")
            }
            .padding(.horizontal, 4)
            ClickUpTaskList(large: false)
        }
        .foregroundStyle(.primary)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Liste des tâches, avec un message quand il n'y a rien à faire. Dans l'onglet, les retards
/// sont repliés dans un groupe en haut ; sur l'Accueil, seulement le jour et l'en-cours.
private struct ClickUpTaskList: View {
    @Environment(ClickUpController.self) private var clickUp
    let large: Bool

    var body: some View {
        let (late, current) = ClickUpController.split(clickUp.tasks, now: Date())
        if clickUp.tasks.isEmpty || (!large && current.isEmpty) {
            VStack(spacing: 4) {
                if clickUp.state == .loading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: large ? 20 : 15))
                    Text(clickUp.tasks.isEmpty ? "Rien à faire" : "Rien pour aujourd'hui")
                        .font(.system(size: large ? 12 : 11))
                }
            }
            .foregroundStyle(.primary.opacity(0.4))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            TimelineView(.everyMinute) { context in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: large ? 4 : 2) {
                        if large, !late.isEmpty {
                            LateGroupHeader(count: late.filter { !$0.isCompleted }.count)
                            if clickUp.showsLateTasks {
                                ForEach(late) { task in
                                    ClickUpTaskRow(task: task, now: context.date, large: large)
                                }
                            }
                        }
                        if large, !late.isEmpty, current.isEmpty {
                            Text("Rien pour aujourd'hui")
                                .font(.system(size: 12))
                                .foregroundStyle(.primary.opacity(0.4))
                                .padding(.horizontal, 6)
                                .padding(.top, 4)
                        }
                        ForEach(current) { task in
                            ClickUpTaskRow(task: task, now: context.date, large: large)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            .animation(.snappy, value: clickUp.tasks)
            .animation(.snappy, value: clickUp.showsLateTasks)
        }
    }
}

/// « En retard · 32 », qui déplie ou replie les tâches d'un jour passé.
private struct LateGroupHeader: View {
    @Environment(ClickUpController.self) private var clickUp
    let count: Int
    @State private var hovering = false

    var body: some View {
        Button {
            clickUp.showsLateTasks.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(clickUp.showsLateTasks ? 90 : 0))
                    .frame(width: 20)
                Text("En retard")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                Spacer(minLength: 0)
                if !clickUp.showsLateTasks {
                    Text("Clic droit sur une tâche pour la reporter")
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.4))
                }
            }
            .foregroundStyle(.red)
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.primary.opacity(hovering ? 0.08 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(clickUp.showsLateTasks ? "Replier les tâches en retard" : "Afficher les tâches en retard")
    }
}

private struct ClickUpTaskRow: View {
    @Environment(ClickUpController.self) private var clickUp
    let task: ClickUpTask
    let now: Date
    let large: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: large ? 9 : 6) {
            Button {
                clickUp.toggle(task)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(task.statusColor, lineWidth: 1.5)
                    if task.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: large ? 9 : 8, weight: .heavy))
                            .foregroundStyle(task.statusColor)
                    }
                }
                .frame(width: large ? 16 : 13, height: large ? 16 : 13)
                .padding(2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(task.isCompleted ? "Rendre son statut à la tâche" : "Marquer comme terminée")

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if let color = task.priorityColor {
                        Image(systemName: "flag.fill")
                            .font(.system(size: large ? 9 : 8))
                            .foregroundStyle(color)
                    }
                    Text(task.name)
                        .font(.system(size: large ? 13.5 : 11.5, weight: .medium))
                        .strikethrough(task.isCompleted)
                        .lineLimit(1)
                }
                if let detail {
                    Text(detail)
                        .font(.system(size: large ? 11.5 : 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(task.isOverdue(now: now) ? Color.red : .primary.opacity(0.5))
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
        .opacity(task.isCompleted ? 0.45 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { clickUp.open(task) }
        .help("Ouvrir dans ClickUp")
        .contextMenu {
            Section("Reporter") {
                ForEach(ClickUpController.Postponement.allCases) { postponement in
                    Button(postponement.label, systemImage: postponement.symbol) {
                        withAnimation(.snappy) { clickUp.postpone(task, to: postponement) }
                    }
                }
            }
            Divider()
            Button("Ouvrir dans ClickUp", systemImage: "arrow.up.forward.app") { clickUp.open(task) }
        }
    }

    /// Échéance (ou retard), puis dans l'onglet le statut et la liste.
    private var detail: String? {
        var parts: [String] = []
        if let due = task.due {
            if due < Calendar.current.startOfDay(for: now) {
                parts.append("En retard · " + due.formatted(.dateTime.day().month(.abbreviated)))
            } else if task.hasTime {
                parts.append(due.formatted(date: .omitted, time: .shortened))
            }
        }
        if large {
            if !task.status.isEmpty { parts.append(task.status) }
            if !task.listName.isEmpty { parts.append(task.listName) }
        } else if task.due == nil, !task.status.isEmpty {
            parts.append(task.status)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension Color {
    /// Violet de ClickUp.
    static let clickUp = Color(red: 0.48, green: 0.41, blue: 0.93)
}

/// Le logo de ClickUp : un chevron vers le haut et une courbe en dessous, chacun dans son dégradé.
struct ClickUpLogo: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let origin = CGPoint(x: (size.width - s) / 2, y: (size.height - s) / 2)
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * s, y: origin.y + y * s) }
            let style = StrokeStyle(lineWidth: s * 0.15, lineCap: .round, lineJoin: .round)

            var chevron = Path()
            chevron.move(to: point(0.2, 0.48))
            chevron.addLine(to: point(0.5, 0.22))
            chevron.addLine(to: point(0.8, 0.48))
            context.stroke(
                chevron,
                with: .linearGradient(
                    Gradient(colors: [Color(red: 1, green: 0.01, blue: 0.94), Color(red: 1, green: 0.78, blue: 0)]),
                    startPoint: point(0.2, 0.4), endPoint: point(0.8, 0.4)),
                style: style)

            var curve = Path()
            curve.move(to: point(0.14, 0.64))
            curve.addQuadCurve(to: point(0.86, 0.64), control: point(0.5, 1.04))
            context.stroke(
                curve,
                with: .linearGradient(
                    Gradient(colors: [Color(red: 0.54, green: 0.19, blue: 0.99), Color(red: 0.29, green: 0.8, blue: 0.98)]),
                    startPoint: point(0.14, 0.75), endPoint: point(0.86, 0.75)),
                style: style)
        }
    }
}
