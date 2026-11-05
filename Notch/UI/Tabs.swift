import SwiftUI

enum NotchTab: String, CaseIterable {
    case home
    case calendar
    case house
    case shelf
    case clipboard
    case notifications
    case claude

    var symbol: String {
        switch self {
        case .home: "music.note.house"
        case .calendar: "calendar"
        case .house: "homekit"
        case .shelf: "tray.full"
        case .clipboard: "doc.on.clipboard"
        case .notifications: "bell"
        case .claude: "sparkle"
        }
    }

    var label: String {
        switch self {
        case .home: "Accueil"
        case .calendar: "Calendrier"
        case .house: "Maison"
        case .shelf: "Étagère"
        case .clipboard: "Presse-papier"
        case .notifications: "Notifications"
        case .claude: "Claude"
        }
    }
}

/// Bandeau du haut de l'encoche ouverte, de part et d'autre de l'encoche :
/// onglets à gauche, actions de l'onglet courant à droite.
struct TopBar: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ClipboardController.self) private var clipboard
    @Environment(ClaudeCodeMonitor.self) private var claudeCode
    @Environment(AlertCenter.self) private var alerts
    @Environment(ShelfController.self) private var shelf

    var body: some View {
        HStack(spacing: 4) {
            ForEach(NotchTab.allCases, id: \.self) { tab in
                TabButton(tab: tab, isSelected: settings.tab == tab) { settings.tab = tab }
                    .overlay(alignment: .topTrailing) {
                        if tab == .claude, claudeCode.waitingCount > 0 {
                            Circle().fill(Color.claude).frame(width: 6, height: 6).offset(x: -3, y: 2)
                        } else if tab == .notifications, alerts.unreadCount > 0, settings.tab != .notifications {
                            Circle().fill(.red).frame(width: 6, height: 6).offset(x: -3, y: 2)
                        }
                    }
            }
            Spacer()
            if settings.tab == .clipboard, !clipboard.items.isEmpty {
                IconButton(symbol: "trash", help: "Vider l'historique (les épinglés sont conservés)") {
                    withAnimation(.snappy) { clipboard.clearUnpinned() }
                }
                .transition(.opacity)
            }
            if settings.tab == .shelf, !shelf.items.isEmpty {
                IconButton(symbol: "airplayaudio", help: "Tout envoyer par AirDrop") { shelf.airDrop(shelf.items) }
                    .transition(.opacity)
                IconButton(symbol: "trash", help: "Vider l'étagère (les fichiers ne sont pas supprimés)") {
                    withAnimation(.snappy) { shelf.removeAll() }
                }
                .transition(.opacity)
            }
            if settings.tab == .notifications, !alerts.history.isEmpty {
                IconButton(symbol: "trash", help: "Effacer l'historique") {
                    withAnimation(.snappy) { alerts.clearHistory() }
                }
                .transition(.opacity)
            }
        }
        .foregroundStyle(.primary)
        .animation(.snappy(duration: 0.2), value: settings.tab)
    }
}

private struct TabButton: View {
    let tab: NotchTab
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 22)
                .background(
                    Capsule().fill(.primary.opacity(isSelected ? 0.2 : hovering ? 0.1 : 0))
                )
                .opacity(isSelected ? 1 : 0.6)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tab.label)
        .onHover { hovering = $0 }
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 22)
                .background(Capsule().fill(.primary.opacity(hovering ? 0.12 : 0)))
                .opacity(hovering ? 1 : 0.6)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

/// Onglet d'accueil : lecteur à gauche, calendrier à droite, et une question à Claude en dessous.
struct HomeTab: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ClaudeAsk.self) private var ask

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 20) {
                ExpandedMusicView()
                    .frame(width: 330)
                Rectangle()
                    .fill(.primary.opacity(0.12))
                    .frame(width: 1)
                    .padding(.vertical, 4)
                CalendarView()
            }
            if ask.cliURL != nil {
                // La réponse s'affiche dans l'onglet Claude.
                ClaudeAskField { settings.tab = .claude }
            }
        }
    }
}
