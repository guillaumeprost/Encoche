import SwiftUI

/// En haut à gauche de l'encoche ouverte : le bouton minuteur, le minuteur en cours et le mode
/// Concentration actif.
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
            if timer.isActive {
                TimerChip(compact: compact)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .fixedSize()
    }
}

/// Minuteur en cours : anneau, temps restant ; un clic le met en pause ou le relance.
private struct TimerChip: View {
    @Environment(TimerController.self) private var timer
    let compact: Bool

    var body: some View {
        Button {
            timer.isPaused ? timer.resume() : timer.pause()
        } label: {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = Int(timer.remaining(at: context.date).rounded(.up))
                HStack(spacing: 5) {
                    ProgressRing(fraction: timer.fraction(at: context.date), tint: .orange, lineWidth: 2)
                        .frame(width: 11, height: 11)
                    Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText())
                    if timer.isPaused {
                        Image(systemName: "pause.fill").font(.system(size: 8, weight: .bold))
                    } else if !compact {
                        Text(timer.kind.label)
                            .font(.system(size: 11, weight: .medium))
                            .opacity(0.75)
                    }
                }
                .foregroundStyle(timer.isPaused ? Color.primary.opacity(0.5) : .orange)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(Color.orange.opacity(0.16)))
                .contentShape(Capsule())
            }
        }
        .buttonStyle(.plain)
        .help(timer.isPaused ? "Reprendre le minuteur" : "Mettre le minuteur en pause")
    }
}
