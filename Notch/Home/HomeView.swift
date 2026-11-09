import SwiftUI

/// Onglet Raccourcis : une tuile par raccourci du dossier « Encoche » de l'app Raccourcis.
struct HomeControlView: View {
    @Environment(HomeShortcuts.self) private var home

    private let columns = [GridItem(.adaptive(minimum: 112, maximum: 150), spacing: 8)]

    var body: some View {
        Group {
            if !home.isLoaded {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if home.shortcuts.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(home.shortcuts) { shortcut in
                            HomeTile(shortcut: shortcut, state: home.states[shortcut.name]) { home.run(shortcut) }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.never)
            }
        }
        .onAppear { home.refresh() }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.2.layers.3d")
                .font(.system(size: 22))
                .foregroundStyle(.primary.opacity(0.5))
            Text(
                home.hasFolder
                    ? "Ajoute des raccourcis dans le dossier « \(HomeShortcuts.folderName) » de Raccourcis"
                    : "Crée un dossier « \(HomeShortcuts.folderName) » dans Raccourcis et mets-y tes raccourcis"
            )
            .font(.system(size: 12))
            .foregroundStyle(.primary.opacity(0.6))
            .multilineTextAlignment(.center)
            Button("Ouvrir Raccourcis") { home.openShortcutsApp() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HomeTile: View {
    let shortcut: HomeShortcuts.Shortcut
    let state: HomeShortcuts.RunState?
    let action: () -> Void

    var body: some View {
        let style = shortcut.style
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(style.tint.opacity(state == .running ? 0.35 : 0.22))
                    stateIcon(style)
                }
                .frame(width: 30, height: 30)

                Text(shortcut.name)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 9)
            .frame(height: 48)
            .glassButton(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Lancer « \(shortcut.name) »")
        .animation(.snappy(duration: 0.2), value: state)
    }

    @ViewBuilder
    private func stateIcon(_ style: HomeShortcutStyle) -> some View {
        switch state {
        case .running:
            ProgressView().controlSize(.mini)
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
        case nil:
            Image(systemName: style.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(style.tint)
        }
    }
}
