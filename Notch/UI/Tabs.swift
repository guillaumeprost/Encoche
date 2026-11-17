import SwiftUI

enum NotchTab: String, CaseIterable {
    case home
    case calendar
    case reminders
    case clickUp
    case music
    case house
    case shelf
    case clipboard
    case notifications
    case claude

    var symbol: String {
        switch self {
        case .home: "music.note.house"
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .clickUp: "checkmark.rectangle.stack"
        case .music: "music.note"
        case .house: "square.2.layers.3d"
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
        case .reminders: "Rappels"
        case .clickUp: "ClickUp"
        case .music: "Musique"
        case .house: "Raccourcis"
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
    @Environment(NotchViewModel.self) private var vm
    @Environment(AppSettings.self) private var settings
    @Environment(ClipboardController.self) private var clipboard
    @Environment(ClaudeCodeMonitor.self) private var claudeCode
    @Environment(AlertCenter.self) private var alerts
    @Environment(ShelfController.self) private var shelf
    @Environment(MusicController.self) private var music
    @Environment(ClickUpController.self) private var clickUp

    /// Onglets affichés : celui de ClickUp seulement pendant que l'app est ouverte.
    private var visibleTabs: [NotchTab] {
        NotchTab.allCases.filter { $0 != .clickUp || clickUp.isActive }
    }

    /// Onglets centrés ; avec une encoche physique, répartis de part et d'autre de la caméra.
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                tabs
                // De chaque côté, les boutons restent dans la place laissée par les onglets.
                let sideSpace = max((geometry.size.width - tabsWidth) / 2 - 8, 0)
                HStack(spacing: 4) {
                    // Minuteur, Sidecar et Concentration à gauche.
                    StatusChips()
                        .frame(maxWidth: sideSpace, alignment: .leading)
                    Spacer()
                    actions
                        .fixedSize()
                        .onGeometryChange(for: CGFloat.self, of: \.size.width) { actionsWidth = $0 }
                        .frame(maxWidth: sideSpace, alignment: .trailing)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .foregroundStyle(.primary)
        .animation(.snappy(duration: 0.2), value: settings.tab)
        .animation(.snappy(duration: 0.2), value: clickUp.isActive)
        // Largeurs réelles des puces et des actions : l'encoche ouverte s'adapte à son contenu.
        .background(alignment: .leading) {
            // Puces dans leur version complète, même quand elles s'affichent compactées.
            StatusChips()
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { chipsWidth = $0 }
        }
        .onChange(of: requiredWidth, initial: true) { vm.topBarWidth = requiredWidth }
    }

    @State private var chipsWidth: CGFloat = 0
    @State private var actionsWidth: CGFloat = 0

    /// Largeur dont la barre a besoin : les onglets au centre, et de chaque côté la place du plus
    /// large des deux bords (puces à gauche, actions à droite), puisque les onglets restent centrés.
    private var requiredWidth: CGFloat {
        tabsWidth + 2 * (max(chipsWidth, actionsWidth) + 16)
    }

    /// Avec une encoche physique, les onglets sont répartis en deux moitiés de part et d'autre.
    private var tabsPerSide: Int { (visibleTabs.count + 1) / 2 }
    private var sideWidth: CGFloat { CGFloat(tabsPerSide) * (TabButton.width + 4) }

    /// Largeur occupée au centre par les onglets (et l'encoche physique).
    private var tabsWidth: CGFloat {
        guard vm.hasPhysicalNotch else { return CGFloat(visibleTabs.count) * (TabButton.width + 4) }
        return 2 * sideWidth + vm.notchSize.width + 16
    }

    @ViewBuilder
    private var tabs: some View {
        if vm.hasPhysicalNotch {
            HStack(spacing: 0) {
                tabRow(Array(visibleTabs.prefix(tabsPerSide)))
                    .frame(width: sideWidth, alignment: .trailing)
                Color.clear.frame(width: vm.notchSize.width + 16)
                tabRow(Array(visibleTabs.dropFirst(tabsPerSide)))
                    .frame(width: sideWidth, alignment: .leading)
            }
        } else {
            tabRow(visibleTabs)
        }
    }

    private func tabRow(_ tabs: [NotchTab]) -> some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.self) { tab in
                TabButton(tab: tab, isSelected: settings.tab == tab) { settings.tab = tab }
                    .overlay(alignment: .topTrailing) {
                        if tab == .claude, claudeCode.waitingCount > 0 {
                            Circle().fill(Color.claude).frame(width: 6, height: 6).offset(x: -3, y: 2)
                        } else if tab == .notifications, alerts.unreadCount > 0, settings.tab != .notifications {
                            Circle().fill(.red).frame(width: 6, height: 6).offset(x: -3, y: 2)
                        }
                    }
            }
        }
    }

    /// Actions de l'onglet courant, au bord droit.
    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 4) {
            if settings.tab == .claude {
                ClaudeUsageLabel()
                    .transition(.opacity)
            }
            // Mini-lecteur, sauf là où le lecteur complet est déjà affiché.
            if music.track != nil, settings.tab != .music, settings.tab != .home {
                MiniMusicControls()
                    .transition(.opacity)
            }
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
    }
}

private struct TabButton: View {
    static let width: CGFloat = 26

    let tab: NotchTab
    let isSelected: Bool
    let action: () -> Void
    @Environment(MusicController.self) private var music
    @State private var hovering = false

    /// Une vidéo du navigateur (YouTube…) : un bouton lecture plutôt qu'une note de musique.
    private var symbol: String {
        tab == .music && music.isPlayingVideo ? "play.rectangle" : tab.symbol
    }

    var body: some View {
        Button(action: action) {
            Group {
                if tab == .claude {
                    // Le petit personnage de Claude Code plutôt qu'un symbole.
                    ClaudeMascot(mood: .idle, color: .primary)
                        .frame(width: 17)
                } else if tab == .clickUp {
                    ClickUpLogo().frame(width: 15, height: 15)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .frame(width: Self.width, height: 22)
            .glassButton(in: Capsule(), tint: isSelected ? .primary.opacity(0.12) : nil, isShown: isSelected || hovering)
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
                .glassButton(in: Capsule(), isShown: hovering)
                .opacity(hovering ? 1 : 0.6)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

/// Onglet d'accueil : lecteur à gauche, calendrier au milieu, rappels à droite, et une question à
/// Claude en dessous.
struct HomeTab: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ClaudeAsk.self) private var ask
    @Environment(ClickUpController.self) private var clickUp
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 20) {
                ExpandedMusicView()
                    .frame(width: 310)
                divider
                CalendarView()
                divider
                RemindersColumn()
                    .frame(width: 140)
                // Les tâches ClickUp dans leur propre colonne, pendant que l'app est ouverte.
                if clickUp.isActive, clickUp.hasToken {
                    divider
                    ClickUpColumn()
                        .frame(width: NotchViewModel.clickUpColumnWidth)
                        .transition(.opacity)
                }
            }
            // Même champ que l'onglet Claude. Par défaut, une nouvelle conversation dans Claude Chat ;
            // la réponse à une question rapide s'affiche dans l'onglet Claude.
            @Bindable var ask = ask
            ClaudeTabField(target: $ask.homeTarget, defaultSession: nil) {
                ask.target = .quickQuestion
                settings.tab = .claude
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.primary.opacity(0.12))
            .frame(width: 1)
            .padding(.vertical, 4)
    }
}
