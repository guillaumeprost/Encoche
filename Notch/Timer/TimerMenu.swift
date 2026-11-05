import SwiftUI

/// Bouton minuteur en haut à gauche de l'encoche ouverte : lancer, mettre en pause, arrêter.
/// Quand un minuteur tourne, le bouton l'affiche (anneau et temps restant).
struct TimerMenu: View {
    @Environment(TimerController.self) private var timer
    @State private var hovering = false

    private static let durations: [Double] = [1, 5, 10, 15, 30, 45, 60]

    var body: some View {
        Menu {
            if timer.isActive {
                Button(timer.isPaused ? "Reprendre" : "Mettre en pause") {
                    timer.isPaused ? timer.resume() : timer.pause()
                }
                Button("Arrêter", role: .destructive) { timer.stop() }
                Divider()
            }
            Button("Pomodoro · 25 min") { timer.start(minutes: 25, kind: .pomodoro) }
            Button("Pause · 5 min") { timer.start(minutes: 5, kind: .pause) }
            Divider()
            ForEach(Self.durations, id: \.self) { minutes in
                Button("Minuteur · \(Int(minutes)) min") { timer.start(minutes: minutes) }
            }
        } label: {
            label
        }
        .plainMenu()
        .onHover { hovering = $0 }
        .help(timer.isActive ? "\(timer.kind.label) : cliquer pour mettre en pause ou arrêter" : "Minuteur")
    }

    @ViewBuilder
    private var label: some View {
        if timer.isActive {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = Int(timer.remaining(at: context.date).rounded(.up))
                HStack(spacing: 5) {
                    ZStack {
                        ProgressRing(fraction: timer.fraction(at: context.date), tint: tint, lineWidth: 2)
                        if timer.isPaused {
                            Image(systemName: "pause.fill").font(.system(size: 5, weight: .black))
                        }
                    }
                    .frame(width: 12, height: 12)
                    Text(Clock.text(remaining))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText())
                }
                .foregroundStyle(timer.isPaused ? Color.primary.opacity(0.55) : tint)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(tint.opacity(hovering ? 0.26 : 0.16)))
                .contentShape(Capsule())
            }
        } else {
            Image(systemName: "timer")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 22)
                .background(Capsule().fill(.primary.opacity(hovering ? 0.12 : 0)))
                .opacity(hovering ? 1 : 0.6)
                .contentShape(Capsule())
        }
    }

    private var tint: Color { timer.tint(remaining: timer.remaining(at: Date())) }
}
