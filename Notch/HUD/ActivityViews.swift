import SwiftUI

/// Anneau de progression des activités en direct.
struct ProgressRing: View {
    /// Entre 0 et 1, ou `nil` pour un anneau qui tourne (durée inconnue).
    let fraction: Double?
    var tint: Color = .white
    var lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.25), lineWidth: lineWidth)
            if let fraction {
                Circle()
                    .trim(from: 0, to: min(max(fraction, 0.02), 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy, value: fraction)
            } else {
                TimelineView(.animation) { context in
                    let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(angle))
                }
            }
        }
    }
}

/// Claude Code travaille : son logo à gauche, l'avancement de son plan à droite.
struct CollapsedClaudeWorkingView: View {
    @Environment(ClaudeCodeMonitor.self) private var monitor
    let slotWidth: CGFloat

    var body: some View {
        let session = monitor.workingSession
        let progress = session?.planProgress
        HStack(spacing: 0) {
            Image(systemName: "sparkle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.claude)
                .symbolEffect(.pulse)
                .frame(width: slotWidth)
            Spacer(minLength: 0)
            Group {
                if let progress, progress.total > 0 {
                    ProgressRing(fraction: Double(progress.done) / Double(progress.total), tint: .claude)
                } else {
                    ProgressRing(fraction: nil, tint: .claude)
                }
            }
            .frame(width: 15, height: 15)
            .frame(width: slotWidth)
        }
        .help(session.map { "\($0.title ?? $0.projectName) · \($0.detail ?? "en cours")" } ?? "Claude travaille")
    }
}

/// Téléchargement en cours : anneau à gauche, pourcentage à droite.
struct CollapsedDownloadView: View {
    @Environment(DownloadMonitor.self) private var downloads
    let slotWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                if downloads.finishedName != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    ProgressRing(fraction: downloads.fraction, tint: .blue)
                        .frame(width: 15, height: 15)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(.blue)
                }
            }
            .frame(width: slotWidth)
            Spacer(minLength: 0)
            Group {
                if downloads.finishedName != nil {
                    Image(systemName: "folder.fill").foregroundStyle(.blue)
                } else {
                    Text(downloads.fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "…")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText())
                        .foregroundStyle(.white)
                }
            }
            .font(.system(size: 12))
            .frame(width: slotWidth)
        }
        .animation(.snappy, value: downloads.finishedName)
        .help(downloads.finishedName.map { "\($0) téléchargé" } ?? downloads.currentName ?? "Téléchargement")
        .onTapGesture { downloads.revealDownloads() }
    }
}

/// Appareil Bluetooth connecté ou déconnecté (AirPods, clavier…), sous l'encoche.
struct DeviceHUDView: View {
    @Environment(BluetoothMonitor.self) private var bluetooth

    var body: some View {
        if let event = bluetooth.lastEvent {
            HStack(spacing: 8) {
                Image(systemName: event.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(event.isConnected ? .white : .white.opacity(0.5))
                    .frame(width: 18)
                Text(event.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let battery = event.battery, event.isConnected {
                    HStack(spacing: 3) {
                        Image(systemName: Self.batterySymbol(battery))
                            .symbolRenderingMode(.hierarchical)
                        Text("\(battery) %")
                    }
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(battery <= 20 ? .red : .white)
                    .transition(.opacity)
                } else {
                    Text(event.isConnected ? "Connecté" : "Déconnecté")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(event.isConnected ? .green : .white.opacity(0.5))
                }
            }
            .foregroundStyle(.white)
            .animation(.snappy, value: event.battery)
        }
    }

    private static func batterySymbol(_ level: Int) -> String {
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
