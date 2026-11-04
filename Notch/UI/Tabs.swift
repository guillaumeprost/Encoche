import SwiftUI

enum NotchTab: String, CaseIterable {
    case home
    case clipboard

    var symbol: String {
        switch self {
        case .home: "music.note.house"
        case .clipboard: "doc.on.clipboard"
        }
    }

    var label: String {
        switch self {
        case .home: "Accueil"
        case .clipboard: "Presse-papier"
        }
    }
}

/// Bandeau du haut de l'encoche ouverte, de part et d'autre de l'encoche :
/// onglets à gauche, actions de l'onglet courant à droite.
struct TopBar: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ClipboardController.self) private var clipboard

    var body: some View {
        HStack(spacing: 4) {
            ForEach(NotchTab.allCases, id: \.self) { tab in
                TabButton(tab: tab, isSelected: settings.tab == tab) { settings.tab = tab }
            }
            Spacer()
            if settings.tab == .clipboard, !clipboard.items.isEmpty {
                IconButton(symbol: "trash", help: "Vider l'historique (les épinglés sont conservés)") {
                    withAnimation(.snappy) { clipboard.clearUnpinned() }
                }
                .transition(.opacity)
            }
        }
        .foregroundStyle(.white)
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
                    Capsule().fill(.white.opacity(isSelected ? 0.2 : hovering ? 0.1 : 0))
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
                .background(Capsule().fill(.white.opacity(hovering ? 0.12 : 0)))
                .opacity(hovering ? 1 : 0.6)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

/// Onglet d'accueil : lecteur à gauche, calendrier à droite.
struct HomeTab: View {
    var body: some View {
        HStack(spacing: 20) {
            ExpandedMusicView()
                .frame(width: 330)
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(width: 1)
                .padding(.vertical, 4)
            CalendarView()
        }
    }
}
