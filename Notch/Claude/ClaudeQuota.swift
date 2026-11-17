import Foundation
import Observation
import SwiftUI

/// Quotas de l'abonnement Claude (5 heures et semaine), comme dans l'app Claude et Claude Code.
///
/// Anthropic les fournit à partir de la connexion de Claude Code, rangée dans le trousseau
/// (« Claude Code-credentials »). Encoche la lit comme Claude Code, avec l'outil `security`, et
/// l'envoie seulement à `api.anthropic.com`. Rien n'est enregistré ni affiché.
/// Ce service n'est pas documenté publiquement : en cas d'échec, l'anneau disparaît.
@Observable
@MainActor
final class ClaudeQuota {
    struct Limit: Equatable {
        /// Part utilisée, entre 0 et 1.
        let used: Double
        let resetsAt: Date?
    }

    private(set) var fiveHour: Limit?
    private(set) var week: Limit?

    @ObservationIgnored private var lastRefresh: Date?
    @ObservationIgnored private var isRefreshing = false

    /// Pour prévenir dans l'encoche quand un quota approche de sa limite.
    @ObservationIgnored var alerts: AlertCenter?
    /// Seuils d'alerte, en part utilisée.
    nonisolated static let thresholds: [Double] = [0.8, 0.95]
    /// Dernier seuil signalé par quota, pour sa période en cours (date de réinitialisation).
    @ObservationIgnored private var alerted: [String: (period: Date?, level: Double)] = [:]
    @ObservationIgnored private var watchTimer: Timer?

    /// Relit les quotas toutes les 5 minutes tant que Claude Code est utilisé, pour prévenir
    /// même quand l'onglet Claude n'est pas ouvert.
    func watch(while isActive: @escaping @MainActor () -> Bool) {
        watchTimer?.invalidate()
        watchTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if isActive() { self?.refresh() }
            }
        }
    }

    /// Relit les quotas (au plus toutes les minutes).
    func refresh() {
        guard !isRefreshing, lastRefresh.map({ Date().timeIntervalSince($0) > 60 }) ?? true else { return }
        isRefreshing = true
        lastRefresh = Date()
        Task {
            let limits = await Self.fetch()
            if let limits {
                fiveHour = limits.fiveHour
                week = limits.week
                checkThresholds()
            }
            isRefreshing = false
        }
    }

    // MARK: - Alertes

    /// Plus haut seuil franchi (`nil` sous le premier).
    nonisolated static func level(for used: Double) -> Double? {
        thresholds.last { used >= $0 }
    }

    /// Prévient une fois par seuil et par période (le compteur repart à la réinitialisation).
    func checkThresholds() {
        for (key, title, limit) in [("five_hour", "Quota de 5 heures", fiveHour), ("week", "Quota hebdomadaire", week)] {
            guard let limit, let level = Self.level(for: limit.used) else { continue }
            let previous = alerted[key]
            // Même période et seuil déjà signalé (la date de réinitialisation bouge de quelques secondes).
            if let previous, previous.level >= level,
                abs((previous.period ?? .distantPast).timeIntervalSince(limit.resetsAt ?? .distantPast)) < 600
            {
                continue
            }
            alerted[key] = (limit.resetsAt, level)
            var body = "\(Int((limit.used * 100).rounded())) % utilisés"
            if let reset = limit.resetsAt { body += " · réinitialisation \(Self.describe(reset))" }
            alerts?.post(
                NotchAlert(
                    icon: .symbol("gauge.with.dots.needle.67percent", level >= 0.95 ? .red : .orange),
                    source: "Claude",
                    title: "\(title) presque atteint",
                    body: body
                ))
        }
    }

    /// « à 18:30 » aujourd'hui, « le jeu. 09:00 » sinon.
    nonisolated static func describe(_ reset: Date) -> String {
        Calendar.current.isDateInToday(reset)
            ? "à \(reset.formatted(date: .omitted, time: .shortened))"
            : "le \(reset.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
    }

    /// Pour les tests : quotas lus sans passer par le service.
    func set(fiveHour: Limit?, week: Limit?) {
        self.fiveHour = fiveHour
        self.week = week
    }

    // MARK: - Lecture

    private nonisolated static func fetch() async -> (fiveHour: Limit?, week: Limit?)? {
        guard let token = await accessToken() else { return nil }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            NSLog("[Encoche] Claude quota request failed: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            return nil
        }
        return (limit(root["five_hour"]), limit(root["seven_day"]))
    }

    nonisolated static func limit(_ value: Any?) -> Limit? {
        guard let entry = value as? [String: Any] else { return nil }
        let percent = (entry["utilization"] as? Double) ?? (entry["used_percentage"] as? Double)
        guard let percent else { return nil }
        var resetsAt: Date?
        if let text = entry["resets_at"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            resetsAt = formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
        } else if let seconds = entry["resets_at"] as? Double {
            resetsAt = Date(timeIntervalSince1970: seconds)
        }
        return Limit(used: min(max(percent / 100, 0), 1), resetsAt: resetsAt)
    }

    /// Jeton de la connexion de Claude Code, lu dans le trousseau avec l'outil `security`.
    /// C'est lui qu'utilise Claude Code : il y a déjà accès, et macOS ne redemande donc pas
    /// d'autorisation quand Claude Code renouvelle sa connexion (ce qui réécrit l'élément).
    private nonisolated static func accessToken() async -> String? {
        guard
            let output = await ProcessRunner.run(
                "/usr/bin/security", ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
            ), output.status == 0,
            let root = try? JSONSerialization.jsonObject(with: Data(output.text.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
                as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String
        else {
            NSLog("[Encoche] Claude credentials not readable")
            return nil
        }
        return token
    }
}

/// Petit anneau du quota hebdomadaire, à droite du champ de l'onglet Claude ; le survol détaille.
struct ClaudeQuotaRing: View {
    @Environment(ClaudeQuota.self) private var quota

    var body: some View {
        // Toujours présente (même vide) pour que le chargement se déclenche à l'affichage.
        ZStack {
            Color.clear.frame(width: 0, height: 0)
            if let week = quota.week {
                ProgressRing(fraction: max(week.used, 0.02), tint: tint(week.used), lineWidth: 2.5)
                    .frame(width: 18, height: 18)
                    .padding(6)
                    .contentShape(Rectangle())
                    .help(details)
                    .transition(.opacity)
            }
        }
        .onAppear { quota.refresh() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                quota.refresh()
            }
        }
    }

    private func tint(_ used: Double) -> Color {
        used >= 0.9 ? .red : used >= 0.75 ? .orange : .claude
    }

    private var details: String {
        func line(_ title: String, _ limit: ClaudeQuota.Limit?) -> String? {
            guard let limit else { return nil }
            var text = "\(title) : \(Int((limit.used * 100).rounded())) %"
            if let reset = limit.resetsAt { text += " · réinitialisation \(ClaudeQuota.describe(reset))" }
            return text
        }
        return [line("Hebdomadaire", quota.week), line("5 heures", quota.fiveHour)].compactMap { $0 }.joined(separator: "\n")
    }
}
