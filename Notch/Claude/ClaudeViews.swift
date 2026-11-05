import SwiftUI

extension Color {
    /// Orange Claude.
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
}

// MARK: - Onglet Claude

struct ClaudeTab: View {
    @Environment(ClaudeCodeMonitor.self) private var monitor
    @Environment(ClaudeAsk.self) private var ask
    @State private var selectedID: String?
    /// Le champ du bas répond à la session choisie (par défaut) ou pose une question rapide.
    @State private var quickQuestion = false

    private var selectedSession: ClaudeCodeSession? {
        let sessions = monitor.sortedSessions
        return sessions.first { $0.id == selectedID } ?? sessions.first
    }

    /// Sessions Claude Code à gauche, discussion à droite, champ sur toute la largeur en bas.
    var body: some View {
        let session = quickQuestion ? nil : selectedSession
        VStack(spacing: 10) {
            HStack(spacing: 20) {
                SessionsPanel(selectedID: $selectedID)
                    .frame(width: 290)
                Rectangle()
                    .fill(.primary.opacity(0.12))
                    .frame(width: 1)
                    .padding(.vertical, 4)
                if let session {
                    SessionConversation(session: session)
                } else {
                    AskPanel()
                }
            }
            ClaudeTabField(
                session: session,
                canReply: selectedSession != nil,
                quickQuestion: $quickQuestion
            )
        }
        .foregroundStyle(.primary)
    }
}

/// Champ du bas de l'onglet Claude : répond à une session, ou pose une question rapide.
private struct ClaudeTabField: View {
    @Environment(ClaudeCodeMonitor.self) private var monitor
    @Environment(ClaudeAsk.self) private var ask
    @Environment(NotchViewModel.self) private var vm
    let session: ClaudeCodeSession?
    let canReply: Bool
    @Binding var quickQuestion: Bool

    @State private var reply = ""
    @State private var feedback: ClaudeReply.Outcome?
    @State private var sending = false
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var ask = ask
        HStack(spacing: 8) {
            targetMenu
            Group {
                if let session {
                    TextField("Répondre à \(session.title ?? session.projectName)…", text: $reply)
                } else {
                    TextField("Demande à Claude…", text: $ask.question)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13.5))
            .focused($focused)
            .onSubmit(send)
            .onExitCommand { focused = false }

            if let feedback { feedbackLabel(feedback) }

            if session == nil, ask.isStreaming {
                Button { ask.cancel() } label: {
                    Image(systemName: "stop.circle.fill").font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .help("Arrêter")
            } else if sending {
                ProgressView().controlSize(.small)
            } else if !(session == nil ? ask.question : reply).isEmpty {
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.claude)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .frame(height: 36)
        .glassEffect(.regular.tint(.primary.opacity(0.08)).interactive(), in: Capsule())
        .animation(.snappy, value: feedback)
        .onChange(of: focused) { vm.holdOpen = focused }
        .onDisappear { vm.holdOpen = false }
    }

    /// Choix de la cible : la session sélectionnée à gauche, ou une question rapide.
    private var targetMenu: some View {
        Menu {
            if canReply {
                Button {
                    quickQuestion = false
                } label: {
                    Label("Répondre à la session choisie", systemImage: "arrowshape.turn.up.left")
                }
            }
            Button {
                quickQuestion = true
            } label: {
                Label("Question rapide à Claude", systemImage: "sparkle")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: session == nil ? "sparkle" : "arrowshape.turn.up.left.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(session?.projectName ?? "Claude")
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.6)
            }
            .foregroundStyle(Color.claude)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(Color.claude.opacity(0.16)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(session == nil ? "Question rapide, sans lien avec tes sessions" : "Répond à la session choisie à gauche")
    }

    @ViewBuilder
    private func feedbackLabel(_ outcome: ClaudeReply.Outcome) -> some View {
        Group {
            switch outcome {
            case .sent(let app):
                Label("Envoyé dans \(app)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .pasted(let app):
                Label("Collé dans \(app) · appuie sur Entrée", systemImage: "doc.on.clipboard.fill").foregroundStyle(.orange)
            case .failed(let reason):
                Label(reason, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
        .transition(.opacity)
    }

    private func send() {
        if let session {
            let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !sending else { return }
            sending = true
            focused = false
            Task {
                let outcome = await monitor.reply(text, to: session.id)
                sending = false
                feedback = outcome
                if case .failed = outcome {} else { reply = "" }
                try? await Task.sleep(for: .seconds(4))
                if feedback == outcome { feedback = nil }
            }
        } else {
            guard !ask.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            ask.send()
        }
    }
}

/// Discussion d'une session : ta dernière demande et la réponse de Claude.
private struct SessionConversation: View {
    let session: ClaudeCodeSession

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    if let prompt = session.prompt {
                        HStack {
                            Spacer(minLength: 40)
                            Text(prompt)
                                .font(.system(size: 12.5))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.claude.opacity(0.22))
                                )
                                .textSelection(.enabled)
                        }
                    }
                    if let message = session.lastMessage {
                        Text(claudeMarkdown(message))
                            .font(.system(size: 13))
                            .foregroundStyle(.primary.opacity(0.9))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if session.state == .working {
                        HStack(spacing: 8) {
                            ThinkingDots()
                            Text(session.detail ?? "Réfléchit…")
                                .font(.system(size: 12))
                                .foregroundStyle(.primary.opacity(0.5))
                                .lineLimit(1)
                        }
                    } else if session.prompt == nil {
                        Text("Pas encore de message dans cette session")
                            .font(.system(size: 12))
                            .foregroundStyle(.primary.opacity(0.45))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 30)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.never)
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: session.lastMessage) { proxy.scrollTo("end", anchor: .bottom) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Question rapide

private struct AskPanel: View {
    @Environment(ClaudeAsk.self) private var ask

    var body: some View {
        if ask.cliURL != nil {
            responseArea
            .contextMenu {
                if !ask.askedQuestion.isEmpty {
                    Button("Nouvelle conversation") { ask.reset() }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("Claude Code introuvable", systemImage: "terminal")
                    .font(.system(size: 12, weight: .semibold))
                Text("Installe la CLI Claude Code et connecte-toi pour poser des questions avec ton abonnement.")
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var responseArea: some View {
        if let error = ask.errorMessage {
            VStack(alignment: .leading, spacing: 4) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                if ask.needsLogin {
                    Text("Dans un terminal, lance `claude` puis `/login`.")
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.6))
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if ask.askedQuestion.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.claude.opacity(0.7))
                Text("Pose une question à Claude dans le champ ci-dessous")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.5))
                    .multilineTextAlignment(.center)
                Text("Entrée pour envoyer · Échap pour quitter le champ")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.primary.opacity(0.35))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 4) {
                        // Échanges précédents de la conversation, en plus discret.
                        ForEach(ask.history) { exchange in
                            Text(exchange.question)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.primary.opacity(0.4))
                                .lineLimit(1)
                            Text(markdown(exchange.answer))
                                .font(.system(size: 13))
                                .foregroundStyle(.primary.opacity(0.6))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 6)
                        }
                        Text(ask.askedQuestion)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.5))
                            .lineLimit(1)
                        if ask.answer.isEmpty && ask.isStreaming {
                            ThinkingDots()
                        } else {
                            Text(markdown(ask.answer))
                                .font(.system(size: 13.5))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 4)
                }
                .scrollIndicators(.never)
                .onChange(of: ask.answer) { proxy.scrollTo("end", anchor: .bottom) }
            }
            .overlay(alignment: .topTrailing) {
                if !ask.history.isEmpty || !ask.answer.isEmpty {
                    Button { ask.reset() } label: {
                        Label("Nouvelle", systemImage: "square.and.pencil")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 7)
                            .frame(height: 18)
                            .background(Capsule().fill(.primary.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Nouvelle conversation")
                }
            }
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

private struct ThinkingDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.claude)
                        .frame(width: 5, height: 5)
                        .opacity(0.3 + 0.7 * max(0, sin(t * 4 - Double(i) * 0.6)))
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// Champ de question à Claude, utilisé dans l'onglet Claude et sur l'accueil.
/// Garde l'encoche ouverte tant qu'il a le focus.
struct ClaudeAskField: View {
    @Environment(ClaudeAsk.self) private var ask
    @Environment(NotchViewModel.self) private var vm
    @FocusState private var focused: Bool
    /// Appelé après l'envoi d'une question (l'accueil bascule alors sur l'onglet Claude).
    var onSend: () -> Void = {}

    var body: some View {
        @Bindable var ask = ask
        HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .foregroundStyle(Color.claude)
            TextField("Demande à Claude…", text: $ask.question)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit(send)
                .onExitCommand { focused = false }
            if ask.isStreaming {
                Button { ask.cancel() } label: {
                    Image(systemName: "stop.circle.fill").font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .help("Arrêter")
            } else if !ask.question.isEmpty {
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.claude)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .glassEffect(.regular.tint(.primary.opacity(0.05)).interactive(), in: Capsule())
        .onChange(of: focused) { vm.holdOpen = focused }
        .onDisappear { vm.holdOpen = false }
    }

    private func send() {
        guard !ask.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        ask.send()
        onSend()
    }
}

// MARK: - Sessions Claude Code

private struct SessionsPanel: View {
    @Environment(ClaudeCodeMonitor.self) private var monitor
    @Binding var selectedID: String?

    /// Session affichée : celle choisie, sinon la plus urgente.
    private var selected: ClaudeCodeSession? {
        let sessions = monitor.sortedSessions
        return sessions.first { $0.id == selectedID } ?? sessions.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !monitor.hooksInstalled {
                title
                VStack(alignment: .leading, spacing: 6) {
                    Text("Affiche l'état de tes sessions et te prévient quand l'une d'elles t'attend.")
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Installer les hooks") { monitor.installHooks() }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    if let error = monitor.hooksError {
                        Text(error).font(.system(size: 10)).foregroundStyle(.orange)
                    }
                }
            } else if let selected {
                if monitor.sessions.count > 1 {
                    chips(selected: selected.id)
                }
                SessionDetail(session: selected)
            } else {
                title
                Text("Aucune session active")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .contextMenu {
            if monitor.hooksInstalled {
                Button("Désinstaller les hooks Claude Code") { monitor.uninstallHooks() }
            }
        }
    }

    private var title: some View {
        Text("Claude Code")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.55))
    }

    /// Une pastille par session, pour passer de l'une à l'autre.
    private func chips(selected: String) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(monitor.sortedSessions) { session in
                    let isSelected = session.id == selected
                    Button { selectedID = session.id } label: {
                        HStack(spacing: 5) {
                            SessionStateIcon(state: session.state)
                                .scaleEffect(0.8)
                                .frame(width: 12)
                            Text(session.projectName)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(.primary.opacity(isSelected ? 0.16 : 0.06)))
                        .foregroundStyle(.primary.opacity(isSelected ? 1 : 0.6))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { Button("Masquer") { monitor.dismiss(session) } }
                }
            }
        }
        .scrollIndicators(.never)
    }
}

/// Ce que fait une session : demande, activité, agents, plan et dernière réponse.
private struct SessionDetail: View {
    @Environment(ClaudeCodeMonitor.self) private var monitor
    let session: ClaudeCodeSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 6) {
                    status
                    if let permission = monitor.permission(for: session.id) {
                        permissionButtons(permission)
                    }
                    ForEach(session.agents) { agent in
                        HStack(spacing: 6) {
                            Group {
                                if agent.isRunning {
                                    ProgressView().controlSize(.mini).tint(Color.claude)
                                } else {
                                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.green)
                                }
                            }
                            .frame(width: 16)
                            Image(systemName: "person.2.fill").font(.system(size: 9)).foregroundStyle(.primary.opacity(0.45))
                            Text(agent.name)
                                .font(.system(size: 12.5))
                                .foregroundStyle(.primary.opacity(agent.isRunning ? 0.85 : 0.5))
                                .lineLimit(1)
                        }
                    }
                    if !session.plan.isEmpty {
                        PlanView(session: session)
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.never)
        }
        .help(session.cwd)
        .contextMenu { Button("Masquer") { monitor.dismiss(session) } }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(session.title ?? session.projectName)
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .layoutPriority(1)
            if session.title != nil {
                Text(session.projectName)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.claude)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { monitor.focus(session.id) } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.6))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ouvrir la session")
        }
    }

    private var status: some View {
        HStack(spacing: 6) {
            SessionStateIcon(state: session.state)
                .frame(width: 16)
            Text(statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(session.state == .waiting ? Color.claude : .primary.opacity(0.85))
                .lineLimit(2)
                .contentTransition(.opacity)
                .animation(.snappy, value: statusText)
        }
    }

    private var statusText: String {
        switch session.state {
        case .idle: return "Prête"
        case .working: return session.detail ?? "Réfléchit…"
        case .waiting: return session.detail ?? "T'attend"
        case .done: return "Terminé"
        }
    }

    private func permissionButtons(_ permission: PendingPermission) -> some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            smallButton("Refuser", color: .red) { monitor.decide(permission, .deny) }
            if permission.canAllowAlways {
                smallButton("Toujours", color: .claude) { monitor.decide(permission, .allowAlways) }
            }
            smallButton("Autoriser", color: .claude, filled: true) { monitor.decide(permission, .allow) }
        }
    }

    private func smallButton(_ label: String, color: Color, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(filled ? .white : color)
                .padding(.horizontal, 11)
                .frame(height: 24)
                .background(Capsule().fill(filled ? color : .primary.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Plan de Claude : avancement et étapes.
private struct PlanView: View {
    let session: ClaudeCodeSession

    var body: some View {
        let progress = session.planProgress
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.primary.opacity(0.5))
                    .frame(width: 16)
                Text("Progression")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.55))
                Text("\(progress.done)/\(progress.total)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.claude)
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    .progressViewStyle(.linear)
                    .tint(Color.claude)
                    .controlSize(.mini)
            }
            ForEach(visibleItems) { item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    icon(item.status)
                        .frame(width: 16)
                    Text(item.content)
                        .font(.system(size: 12.5, weight: item.status == .inProgress ? .semibold : .regular))
                        .foregroundStyle(.primary.opacity(item.status == .completed ? 0.4 : item.status == .inProgress ? 0.95 : 0.65))
                        .strikethrough(item.status == .completed, color: .primary.opacity(0.3))
                        .lineLimit(1)
                }
            }
        }
        .padding(.top, 2)
    }

    /// L'étape en cours et les suivantes : la barre résume déjà celles qui sont faites.
    /// Plan terminé : on montre les dernières étapes.
    private var visibleItems: [ClaudeCodeSession.PlanItem] {
        let plan = session.plan
        guard let start = plan.firstIndex(where: { $0.status != .completed }) else {
            return Array(plan.suffix(3))
        }
        return Array(plan[start...].prefix(6))
    }

    @ViewBuilder
    private func icon(_ status: ClaudeCodeSession.PlanItem.Status) -> some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 11.5)).foregroundStyle(.green)
        case .inProgress:
            Image(systemName: "circle.dotted.circle").font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.claude)
                .symbolEffect(.pulse)
        case .pending:
            Image(systemName: "circle").font(.system(size: 11.5)).foregroundStyle(.primary.opacity(0.35))
        }
    }
}

/// Markdown simple (gras, italique, code) des réponses de Claude.
func claudeMarkdown(_ text: String) -> AttributedString {
    (try? AttributedString(
        markdown: text,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    )) ?? AttributedString(text)
}

struct SessionStateIcon: View {
    let state: ClaudeCodeSession.State

    var body: some View {
        switch state {
        case .idle:
            Image(systemName: "circle").foregroundStyle(.primary.opacity(0.4)).font(.system(size: 9))
        case .working:
            ProgressView().controlSize(.mini).tint(Color.claude)
        case .waiting:
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(Color.claude)
                .font(.system(size: 11))
                .symbolEffect(.pulse)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 12))
        }
    }
}

// MARK: - Encoche repliée

/// Signal discret de part et d'autre de l'encoche quand une session t'attend ou vient de finir.
struct CollapsedClaudeView: View {
    @Environment(ClaudeCodeMonitor.self) private var monitor
    let slotWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.claude)
                .symbolEffect(.pulse, isActive: monitor.waitingCount > 0)
                .frame(width: slotWidth)
            Spacer(minLength: 0)
            Group {
                if monitor.waitingCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "hand.raised.fill")
                        if monitor.waitingCount > 1 {
                            Text("\(monitor.waitingCount)").font(.system(size: 11, weight: .bold))
                        }
                    }
                    .foregroundStyle(Color.claude)
                    .symbolEffect(.pulse)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .frame(width: slotWidth)
        }
    }
}
