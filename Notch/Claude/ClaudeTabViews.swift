import SwiftUI

extension Color {
    /// Orange Claude.
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
}

// MARK: - Onglet Claude

struct ClaudeTab: View {
    @Environment(ClaudeCodeMonitor.self) private var monitor
    @Environment(ClaudeAsk.self) private var ask

    /// Session affichée : celle choisie (pastilles ou champ), sinon la plus urgente.
    private var selectedSession: ClaudeCodeSession? {
        let sessions = monitor.sortedSessions
        if case .session(let id) = ask.target, let chosen = sessions.first(where: { $0.id == id }) { return chosen }
        return sessions.first
    }

    /// Sélecteur des dernières sessions en haut, session choisie à gauche, discussion à droite,
    /// champ sur toute la largeur en bas.
    var body: some View {
        VStack(spacing: 10) {
            if monitor.hooksInstalled, monitor.sessions.count > 1 {
                SessionChips(
                    selectedID: Binding(
                        get: { selectedSession?.id },
                        set: { id in ask.target = id.map { .session($0) } }
                    ))
            }
            HStack(spacing: 20) {
                SessionsPanel(session: selectedSession)
                    .frame(width: 290)
                Rectangle()
                    .fill(.primary.opacity(0.12))
                    .frame(width: 1)
                    .padding(.vertical, 4)
                switch ClaudeTabField.resolve(ask.target, default: selectedSession, among: monitor.sessions) {
                case .session(let session): SessionConversation(session: session)
                case .newConversation: NewConversationHint()
                case .quickQuestion: AskPanel()
                }
            }
            HStack(spacing: 6) {
                @Bindable var ask = ask
                ClaudeTabField(target: $ask.target, defaultSession: selectedSession)
                // Quota hebdomadaire de l'abonnement, comme dans l'app Claude.
                ClaudeQuotaRing()
            }
        }
        .foregroundStyle(.primary)
    }
}

/// Nouvelle conversation choisie : ce qui va se passer.
private struct NewConversationHint: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 20))
                .foregroundStyle(Color.claude.opacity(0.7))
            Text("Ton message ouvrira une nouvelle conversation dans l'app Claude")
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Champ Claude (onglet Claude et accueil) : répond à une de tes dernières conversations, en
/// démarre une nouvelle dans l'app Claude, ou pose une question rapide.
struct ClaudeTabField: View {
    @Environment(ClaudeCodeMonitor.self) private var monitor
    @Environment(ClaudeAsk.self) private var ask
    @Environment(NotchViewModel.self) private var vm
    /// Destinataire choisi dans le menu (propre à chaque champ : accueil, onglet Claude).
    @Binding var target: ClaudeAsk.Target?
    /// Session visée quand rien n'a été choisi ; sans session, une nouvelle conversation.
    let defaultSession: ClaudeCodeSession?
    /// Appelé après l'envoi d'une question rapide (l'accueil bascule alors sur l'onglet Claude).
    var onQuickQuestion: () -> Void = {}

    @State private var reply = ""
    @State private var feedback: ClaudeReply.Outcome?
    @State private var sending = false
    @FocusState private var focused: Bool

    /// Destinataire effectif.
    enum Resolved {
        case session(ClaudeCodeSession)
        case newConversation
        case quickQuestion
    }

    static func resolve(
        _ target: ClaudeAsk.Target?, default session: ClaudeCodeSession?,
        among sessions: [ClaudeCodeSession]
    ) -> Resolved {
        switch target {
        case .session(let id):
            if let chosen = sessions.first(where: { $0.id == id }) { return .session(chosen) }
        case .newConversation: return .newConversation
        case .quickQuestion: return .quickQuestion
        case nil: break
        }
        return session.map { .session($0) } ?? .newConversation
    }

    private var resolved: Resolved { Self.resolve(target, default: defaultSession, among: monitor.sessions) }

    var body: some View {
        @Bindable var ask = ask
        let resolved = resolved
        HStack(spacing: 8) {
            targetMenu(resolved)
            Group {
                switch resolved {
                case .session(let session):
                    TextField("Répondre à \(session.title ?? session.projectName)…", text: $reply)
                case .newConversation:
                    TextField("Nouvelle conversation dans Claude…", text: $reply)
                case .quickQuestion:
                    TextField("Question rapide à Claude…", text: $ask.question)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13.5))
            .focused($focused)
            .onSubmit(send)
            .onExitCommand { focused = false }

            if let feedback { feedbackLabel(feedback) }

            if case .quickQuestion = resolved, ask.isStreaming {
                Button {
                    ask.cancel()
                } label: {
                    Image(systemName: "stop.circle.fill").font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .help("Arrêter")
            } else if sending {
                ProgressView().controlSize(.small)
            } else if !currentText(resolved).isEmpty {
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

    private func currentText(_ resolved: Resolved) -> String {
        if case .quickQuestion = resolved { return ask.question }
        return reply
    }

    /// Choix du destinataire : tes 3 dernières conversations, une nouvelle, ou une question rapide.
    private func targetMenu(_ resolved: Resolved) -> some View {
        Menu {
            let recent = monitor.sortedSessions.prefix(3)
            if !recent.isEmpty {
                Section("Dernières conversations") {
                    ForEach(Array(recent)) { session in
                        Button {
                            target = .session(session.id)
                        } label: {
                            Label(
                                session.title ?? session.projectName,
                                systemImage: session.state == .inactive ? "moon.zzz" : "bubble.left.and.text.bubble.right")
                        }
                    }
                }
            }
            Button {
                target = .newConversation
            } label: {
                Label("Nouvelle conversation dans Claude", systemImage: "square.and.pencil")
            }
            Divider()
            Button {
                target = .quickQuestion
            } label: {
                Label("Question rapide (réponse dans l'encoche)", systemImage: "sparkle")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: chipSymbol(resolved))
                    .font(.system(size: 11, weight: .semibold))
                Text(chipTitle(resolved))
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: 150)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.6)
            }
            .foregroundStyle(Color.claude)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(Color.claude.opacity(0.16)))
        }
        .plainMenu()
        .help("Choisir la conversation")
    }

    private func chipTitle(_ resolved: Resolved) -> String {
        switch resolved {
        case .session(let session): session.title ?? session.projectName
        case .newConversation: "Nouvelle conversation"
        case .quickQuestion: "Question rapide"
        }
    }

    private func chipSymbol(_ resolved: Resolved) -> String {
        switch resolved {
        case .session: "arrowshape.turn.up.left.fill"
        case .newConversation: "square.and.pencil"
        case .quickQuestion: "sparkle"
        }
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
        let resolved = resolved
        if case .quickQuestion = resolved {
            guard !ask.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            ask.send()
            onQuickQuestion()
            return
        }
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        focused = false
        Task {
            let outcome: ClaudeReply.Outcome
            if case .session(let session) = resolved {
                outcome = await monitor.reply(text, to: session.id)
            } else {
                outcome = await ClaudeReply.startNewConversation(text)
                // La nouvelle conversation devient la plus récente : on y répondra ensuite.
                if case .sent = outcome, target == .newConversation { target = nil }
            }
            sending = false
            feedback = outcome
            if case .failed = outcome {} else { reply = "" }
            try? await Task.sleep(for: .seconds(4))
            if feedback == outcome { feedback = nil }
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
