import SwiftUI

/// En haut à gauche de l'encoche ouverte : le bouton minuteur (qui affiche le minuteur en cours)
/// et le mode Concentration actif.
/// Ils se réduisent à leur icône quand la place manque (encoche physique au milieu).
struct StatusChips: View {
    @Environment(FocusMonitor.self) private var focus
    @Environment(TimerController.self) private var timer

    var body: some View {
        ViewThatFits(in: .horizontal) {
            chips(compact: false)
            chips(compact: true)
        }
        .animation(.snappy, value: focus.activeMode)
        .animation(.snappy, value: timer.isActive)
    }

    private func chips(compact: Bool) -> some View {
        HStack(spacing: 6) {
            TimerMenu()
            SidecarButton()
            if let mode = focus.activeMode {
                HStack(spacing: 4) {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 10, weight: .semibold))
                    if !compact {
                        Text(mode.name)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.indigo)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(Color.indigo.opacity(0.18)))
                .help("Concentration : \(mode.name)")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .fixedSize()
    }
}
