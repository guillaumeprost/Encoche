import AppKit
import Observation
import SwiftUI

/// Appels de l'iPhone sur le Mac (Continuité).
///
/// macOS les annonce par une alerte de FaceTime avec Accepter / Refuser. Encoche la laisse à
/// l'écran (la fermer refuserait l'appel), la double dans l'encoche avec les mêmes boutons,
/// puis affiche la durée de l'appel en activité en direct tant que le micro est utilisé.
@Observable
@MainActor
final class CallMonitor {
    enum State: Equatable {
        case idle
        case ringing(caller: String)
        case ongoing(caller: String, since: Date)
    }

    private(set) var state: State = .idle

    @ObservationIgnored var alerts: AlertCenter?
    @ObservationIgnored var privacy: PrivacyMonitor?
    @ObservationIgnored private var current: BannerSuppressor.CallAlert?
    @ObservationIgnored private var alertID: UUID?
    @ObservationIgnored private var endCheck: Task<Void, Never>?

    var isActive: Bool { state != .idle }

    /// Alertes d'appel actuellement affichées par macOS (à chaque passage).
    func update(_ calls: [BannerSuppressor.CallAlert]) {
        if let call = calls.first {
            current = call
            if case .ringing(let caller) = state, caller == call.caller { return }
            if case .ongoing = state { return }
            state = .ringing(caller: call.caller)
            announce(call)
        } else if case .ringing = state {
            // L'alerte a disparu sans réponse d'ici : appel refusé, manqué ou pris sur l'iPhone.
            finish()
        }
    }

    func answer() {
        guard let call = current, let action = call.answerAction, case .ringing(let caller) = state else { return }
        AXUIElementPerformAction(call.element, action as CFString)
        dismissAlert()
        state = .ongoing(caller: caller, since: Date())
        watchForEnd()
    }

    func decline() {
        guard let call = current, let action = call.declineAction else { return }
        AXUIElementPerformAction(call.element, action as CFString)
        finish()
    }

    private func announce(_ call: BannerSuppressor.CallAlert) {
        dismissAlert()
        // La même annonce relayée depuis FaceTime ferait doublon.
        alerts?.muteRelayedNotifications(from: "com.apple.FaceTime", for: 30)
        var alert = NotchAlert(
            icon: .symbol("phone.fill", .green),
            source: "Appel",
            title: call.caller,
            body: call.detail ?? "Appel entrant"
        )
        var buttons: [NotchAlert.Button] = []
        if call.declineAction != nil {
            buttons.append(.init(label: "Refuser", role: .destructive) { [weak self] in self?.decline() })
        }
        if call.answerAction != nil {
            buttons.append(.init(label: "Répondre", role: .primary) { [weak self] in self?.answer() })
        }
        alert.buttons = buttons
        alertID = alert.id
        alerts?.post(alert)
    }

    /// L'appel se termine quand le micro n'est plus utilisé (après l'avoir été).
    private func watchForEnd() {
        endCheck?.cancel()
        endCheck = Task { [weak self] in
            var micSeen = false
            var idleSeconds = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if self.privacy?.isMicrophoneInUse == true {
                    micSeen = true
                    idleSeconds = 0
                } else {
                    idleSeconds += 1
                    // Micro coupé 3 s après l'avoir été, ou jamais utilisé au bout de 20 s.
                    if (micSeen && idleSeconds >= 3) || (!micSeen && idleSeconds >= 20) {
                        self.finish()
                        return
                    }
                }
            }
        }
    }

    private func finish() {
        endCheck?.cancel()
        dismissAlert()
        current = nil
        state = .idle
    }

    private func dismissAlert() {
        if let alertID { alerts?.dismiss(alertID: alertID) }
        alertID = nil
    }
}

/// Appel : téléphone vert à gauche ; qui appelle (sonnerie) ou durée (en cours) à droite.
struct CollapsedCallView: View {
    @Environment(CallMonitor.self) private var calls
    let slotWidth: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            CollapsedActivityLayout(slotWidth: slotWidth) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                    .symbolEffect(.wiggle, isActive: isRinging)
            } trailing: {
                Text(trailingText(at: context.date))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.trailing, 4)
            }
        }
    }

    private var isRinging: Bool {
        if case .ringing = calls.state { return true }
        return false
    }

    private func trailingText(at date: Date) -> String {
        switch calls.state {
        case .ongoing(_, let since):
            let seconds = Int(date.timeIntervalSince(since))
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        case .ringing:
            return "Appel"
        case .idle:
            return ""
        }
    }
}
