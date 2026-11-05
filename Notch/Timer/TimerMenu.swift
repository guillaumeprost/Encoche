import SwiftUI

/// Bouton minuteur en haut à droite de l'encoche ouverte : lancer, mettre en pause, arrêter.
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
            Image(systemName: timer.isActive ? "timer.circle.fill" : "timer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(timer.isActive ? Color.orange : Color.primary)
                .frame(width: 26, height: 22)
                .background(Capsule().fill(.primary.opacity(hovering ? 0.12 : 0)))
                .opacity(hovering || timer.isActive ? 1 : 0.6)
                .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help("Minuteur")
    }
}
