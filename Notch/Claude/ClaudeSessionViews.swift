import SwiftUI

// MARK: - Sessions Claude Code

struct SessionsPanel: View {
    @Environment(ClaudeCodeMonitor.self) private var monitor
    /// Session affichée : celle choisie, sinon la plus urgente.
    let session: ClaudeCodeSession?

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
            } else if let session {
                SessionDetail(session: session)
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
}

/// Sélecteur des dernières sessions, sur toute la largeur de l'encoche.
struct SessionChips: View {
    @Environment(ClaudeCodeMonitor.self) private var monitor
    @Binding var selectedID: String?

    var body: some View {
        let sessions = Array(monitor.sortedSessions.prefix(ClaudeCodeMonitor.recentLimit))
        let selected = sessions.first { $0.id == selectedID }?.id ?? sessions.first?.id
        HStack(spacing: 6) {
            ForEach(sessions) { session in
                let isSelected = session.id == selected
                Button {
                    selectedID = session.id
                } label: {
                    HStack(spacing: 6) {
                        SessionStateIcon(state: session.state)
                            .scaleEffect(0.85)
                            .frame(width: 13)
                        Text(session.title ?? session.projectName)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .glassButton(in: Capsule(), tint: isSelected ? .primary.opacity(0.12) : nil)
                    .foregroundStyle(.primary.opacity(isSelected ? 1 : 0.6))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(session.title.map { "\($0) · \(session.projectName)" } ?? session.projectName)
                .contextMenu { Button("Masquer") { monitor.dismiss(session) } }
            }
        }
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
            Button {
                monitor.focus(session.id)
            } label: {
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
        case .inactive: return "Session fermée"
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
                .glassButton(in: Capsule(), tint: filled ? color : nil)
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
        case .inactive:
            Image(systemName: "moon.zzz.fill").foregroundStyle(.primary.opacity(0.35)).font(.system(size: 9))
        }
    }
}

// MARK: - Encoche repliée

/// Signal discret de part et d'autre de l'encoche quand une session t'attend ou vient de finir.
struct CollapsedClaudeView: View {
    @Environment(ClaudeCodeMonitor.self) private var monitor
    let slotWidth: CGFloat

    var body: some View {
        CollapsedActivityLayout(slotWidth: slotWidth) {
            ClaudeMascot(mood: monitor.waitingCount > 0 ? .waiting : .idle)
                .frame(width: 28)
        } trailing: {
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
        }
    }
}
