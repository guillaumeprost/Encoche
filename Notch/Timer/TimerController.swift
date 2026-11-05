import AppKit
import Observation
import SwiftUI

/// Minuteur et Pomodoro, lancés depuis l'encoche et affichés en activité en direct.
@Observable
@MainActor
final class TimerController {
    enum Kind: String, Equatable {
        case timer
        /// 25 minutes de travail, suivies d'une pause proposée.
        case pomodoro
        case pause

        var label: String {
            switch self {
            case .timer: "Minuteur"
            case .pomodoro: "Pomodoro"
            case .pause: "Pause"
            }
        }

        var symbol: String {
            switch self {
            case .timer: "timer"
            case .pomodoro: "brain.head.profile"
            case .pause: "cup.and.saucer.fill"
            }
        }
    }

    private(set) var kind: Kind = .timer
    private(set) var duration: TimeInterval = 0
    /// Fin prévue, quand il tourne.
    private(set) var endDate: Date?
    /// Temps restant, quand il est en pause.
    private(set) var pausedRemaining: TimeInterval?

    var isActive: Bool { endDate != nil || pausedRemaining != nil }
    var isPaused: Bool { pausedRemaining != nil }

    @ObservationIgnored var alerts: AlertCenter?
    @ObservationIgnored private var finishTask: Task<Void, Never>?

    private static let storeKey = "runningTimer"

    /// Reprend un minuteur en cours après un redémarrage d'Encoche (mise à jour…).
    init() {
        guard let saved = UserDefaults.standard.dictionary(forKey: Self.storeKey),
              let kind = (saved["kind"] as? String).flatMap(Kind.init),
              let duration = saved["duration"] as? Double else { return }
        self.kind = kind
        self.duration = duration
        if let paused = saved["pausedRemaining"] as? Double {
            pausedRemaining = paused
        } else if let end = saved["endDate"] as? Date, end > Date() {
            schedule(endDate: end)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.storeKey)
        }
    }

    private func save() {
        guard isActive else {
            UserDefaults.standard.removeObject(forKey: Self.storeKey)
            return
        }
        var state: [String: Any] = ["kind": kind.rawValue, "duration": duration]
        if let endDate { state["endDate"] = endDate }
        if let pausedRemaining { state["pausedRemaining"] = pausedRemaining }
        UserDefaults.standard.set(state, forKey: Self.storeKey)
    }

    func remaining(at date: Date) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return 0 }
        return max(endDate.timeIntervalSince(date), 0)
    }

    /// Part restante, de 1 (début) à 0 (fin).
    func fraction(at date: Date) -> Double {
        duration > 0 ? remaining(at: date) / duration : 0
    }

    /// Couleur du minuteur : turquoise en pause café, rouge la dernière minute, orange sinon.
    func tint(remaining: TimeInterval) -> Color {
        if kind == .pause { return .teal }
        return remaining <= 60 && !isPaused ? .red : .orange
    }

    func start(minutes: Double, kind: Kind = .timer) {
        self.kind = kind
        duration = minutes * 60
        pausedRemaining = nil
        schedule(endDate: Date().addingTimeInterval(duration))
    }

    func pause() {
        guard let endDate else { return }
        pausedRemaining = max(endDate.timeIntervalSinceNow, 0)
        self.endDate = nil
        finishTask?.cancel()
        save()
    }

    func resume() {
        guard let pausedRemaining else { return }
        self.pausedRemaining = nil
        schedule(endDate: Date().addingTimeInterval(pausedRemaining))
    }

    func stop() {
        finishTask?.cancel()
        endDate = nil
        pausedRemaining = nil
        save()
    }

    private func schedule(endDate: Date) {
        self.endDate = endDate
        save()
        finishTask?.cancel()
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(endDate.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    private func finish() {
        let finished = kind
        stop()
        NSSound(named: "Glass")?.play()
        var alert = NotchAlert(
            icon: .symbol(finished.symbol, .orange),
            source: finished.label,
            title: finished == .pomodoro ? "Pomodoro terminé" : finished == .pause ? "Fin de la pause" : "Minuteur terminé",
            body: finished == .pomodoro ? "Bravo ! Une petite pause ?" : nil
        )
        // Le Pomodoro propose d'enchaîner : pause après le travail, travail après la pause.
        switch finished {
        case .pomodoro:
            alert.buttons = [
                .init(label: "Plus tard", role: .normal) {},
                .init(label: "Pause 5 min", role: .primary) { [weak self] in self?.start(minutes: 5, kind: .pause) },
            ]
        case .pause:
            alert.buttons = [
                .init(label: "Plus tard", role: .normal) {},
                .init(label: "Pomodoro", role: .primary) { [weak self] in self?.start(minutes: 25, kind: .pomodoro) },
            ]
        case .timer:
            break
        }
        alerts?.post(alert)
    }
}
