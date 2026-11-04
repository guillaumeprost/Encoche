import SwiftUI

extension Color {
    /// Orange Claude.
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
}

// MARK: - Onglet Claude

struct ClaudeTab: View {
    var body: some View {
        HStack(spacing: 20) {
            AskPanel()
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(width: 1)
                .padding(.vertical, 4)
            SessionsPanel()
                .frame(width: 220)
        }
        .foregroundStyle(.white)
    }
}

// MARK: - Question rapide

private struct AskPanel: View {
    @Environment(ClaudeAsk.self) private var ask
    @Environment(NotchViewModel.self) private var vm
    @FocusState private var focused: Bool

    var body: some View {
        if ask.cliURL != nil {
            VStack(alignment: .leading, spacing: 8) {
                inputField
                responseArea
            }
            .onChange(of: focused) { vm.holdOpen = focused }
            .onDisappear { vm.holdOpen = false }
            .contextMenu {
                if !ask.askedQuestion.isEmpty {
                    Button("Effacer la réponse") { ask.reset() }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("Claude Code introuvable", systemImage: "terminal")
                    .font(.system(size: 12, weight: .semibold))
                Text("Installe la CLI Claude Code et connecte-toi pour poser des questions avec ton abonnement.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var inputField: some View {
        @Bindable var ask = ask
        return HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .foregroundStyle(Color.claude)
            TextField("Demande à Claude…", text: $ask.question)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit { ask.send() }
                .onExitCommand { focused = false }
            if ask.isStreaming {
                Button { ask.cancel() } label: {
                    Image(systemName: "stop.circle.fill").font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .help("Arrêter")
            } else if !ask.question.isEmpty {
                Button { ask.send() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.claude)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .glassEffect(.regular.tint(.white.opacity(0.05)).interactive(), in: Capsule())
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
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if ask.askedQuestion.isEmpty {
            Text("Entrée pour envoyer · Échap pour quitter le champ")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 4)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ask.askedQuestion)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                        if ask.answer.isEmpty && ask.isStreaming {
                            ThinkingDots()
                        } else {
                            Text(markdown(ask.answer))
                                .font(.system(size: 12.5))
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

// MARK: - Sessions Claude Code

private struct SessionsPanel: View {
    @Environment(ClaudeCodeMonitor.self) private var monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Claude Code")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
            }

            if !monitor.hooksInstalled {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Affiche l'état de tes sessions et te prévient quand l'une d'elles t'attend.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Installer les hooks") { monitor.installHooks() }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    if let error = monitor.hooksError {
                        Text(error).font(.system(size: 10)).foregroundStyle(.orange)
                    }
                }
            } else if monitor.sessions.isEmpty {
                Text("Aucune session active")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 4) {
                        ForEach(monitor.sortedSessions) { session in
                            SessionRow(session: session)
                                .contextMenu {
                                    Button("Masquer") { monitor.dismiss(session) }
                                }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .contextMenu {
            if monitor.hooksInstalled {
                Button("Désinstaller les hooks Claude Code") { monitor.uninstallHooks() }
            }
        }
    }
}

private struct SessionRow: View {
    let session: ClaudeCodeSession

    var body: some View {
        HStack(spacing: 8) {
            SessionStateIcon(state: session.state)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.projectName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(session.state == .waiting ? Color.claude : .white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(session.state == .waiting ? Color.claude.opacity(0.18) : .white.opacity(0.06))
        )
        .help(session.cwd)
    }

    private var subtitle: String {
        switch session.state {
        case .idle: return "Prête"
        case .working: return session.detail.map { "En cours · \($0)" } ?? "En cours…"
        case .waiting: return session.detail ?? "T'attend"
        case .done: return "Terminé"
        }
    }
}

struct SessionStateIcon: View {
    let state: ClaudeCodeSession.State

    var body: some View {
        switch state {
        case .idle:
            Image(systemName: "circle").foregroundStyle(.white.opacity(0.4)).font(.system(size: 9))
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
