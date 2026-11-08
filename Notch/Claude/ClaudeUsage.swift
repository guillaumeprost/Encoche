import Foundation
import Observation
import SwiftUI

/// Consommation de Claude Code (tokens), calculée à partir des transcriptions
/// (`~/.claude/projects/**/*.jsonl`) : rien n'est demandé en ligne.
///
/// Les fichiers sont lus de façon incrémentale : seules les lignes ajoutées depuis la
/// dernière lecture sont analysées. Chaque réponse n'est comptée qu'une fois (une même
/// réponse est écrite sur plusieurs lignes).
@Observable
@MainActor
final class ClaudeUsage {
    struct Totals: Equatable, Sendable {
        var input = 0
        var output = 0
        var cacheWrite = 0
        var cacheRead = 0

        var total: Int { input + output + cacheWrite + cacheRead }

        static func + (lhs: Totals, rhs: Totals) -> Totals {
            Totals(
                input: lhs.input + rhs.input, output: lhs.output + rhs.output,
                cacheWrite: lhs.cacheWrite + rhs.cacheWrite, cacheRead: lhs.cacheRead + rhs.cacheRead)
        }
    }

    private(set) var today = Totals()
    private(set) var week = Totals()
    private(set) var isLoaded = false

    @ObservationIgnored private let scanner = Scanner()
    @ObservationIgnored private var isRefreshing = false

    /// Relit les transcriptions (les nouvelles lignes seulement).
    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            let days = await scanner.scan()
            let calendar = Calendar.current
            let startOfToday = calendar.startOfDay(for: Date())
            let weekStart = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
            today = days[startOfToday] ?? Totals()
            week = days.filter { $0.key >= weekStart }.values.reduce(Totals(), +)
            isLoaded = true
            isRefreshing = false
        }
    }

    /// « 12,3 M », « 845 k ».
    nonisolated static func format(_ tokens: Int) -> String {
        switch tokens {
        case 1_000_000...: return String(format: "%.1f M", Double(tokens) / 1_000_000).replacingOccurrences(of: ".", with: ",")
        case 1_000...: return "\(tokens / 1_000) k"
        default: return "\(tokens)"
        }
    }

    // MARK: - Lecture

    /// Lecture des fichiers hors du fil principal, en gardant où on s'est arrêté dans chacun.
    private actor Scanner {
        private var offsets: [String: UInt64] = [:]
        /// Réponses déjà comptées, avec leur jour (oubliées avec les jours trop anciens).
        private var seenMessages: [String: Date] = [:]
        private var days: [Date: Totals] = [:]
        private let isoFormatter: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()

        func scan() -> [Date: Totals] {
            let fm = FileManager.default
            let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
            let since = Date().addingTimeInterval(-8 * 86_400)
            let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
            guard let files = fm.enumerator(at: root, includingPropertiesForKeys: keys) else { return days }

            var seenPaths: Set<String> = []
            for case let url as URL in files where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                    (values.contentModificationDate ?? .distantPast) >= since
                else { continue }
                seenPaths.insert(url.path)
                let size = UInt64(values.fileSize ?? 0)
                let offset = offsets[url.path] ?? 0
                guard size > offset else { continue }
                offsets[url.path] = offset + read(url, from: offset)
            }
            // On ne garde que la dernière semaine.
            let oldest = Calendar.current.startOfDay(for: since)
            days = days.filter { $0.key >= oldest }
            seenMessages = seenMessages.filter { $0.value >= oldest }
            offsets = offsets.filter { seenPaths.contains($0.key) }
            return days
        }

        /// Analyse les lignes complètes à partir de `offset` ; renvoie le nombre d'octets lus.
        /// Une dernière ligne en cours d'écriture est laissée pour la prochaine lecture.
        private func read(_ url: URL, from offset: UInt64) -> UInt64 {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return 0 }
            defer { try? handle.close() }
            try? handle.seek(toOffset: offset)
            guard let data = try? handle.readToEnd(),
                let lastNewline = data.lastIndex(of: UInt8(ascii: "\n"))
            else { return 0 }
            let complete = data[data.startIndex...lastNewline]
            let marker = Data("\"usage\"".utf8)

            for line in complete.split(separator: UInt8(ascii: "\n")) where line.range(of: marker) != nil {
                guard let entry = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                    let message = entry["message"] as? [String: Any],
                    let usage = message["usage"] as? [String: Any],
                    let stamp = entry["timestamp"] as? String,
                    let date = isoFormatter.date(from: stamp)
                else { continue }
                // Une réponse est écrite sur plusieurs lignes : on ne la compte qu'une fois.
                let id = (message["id"] as? String ?? "") + (entry["requestId"] as? String ?? "")
                let day = Calendar.current.startOfDay(for: date)
                guard !id.isEmpty, seenMessages.updateValue(day, forKey: id) == nil else { continue }

                var totals = days[day] ?? Totals()
                totals.input += usage["input_tokens"] as? Int ?? 0
                totals.output += usage["output_tokens"] as? Int ?? 0
                totals.cacheWrite += usage["cache_creation_input_tokens"] as? Int ?? 0
                totals.cacheRead += usage["cache_read_input_tokens"] as? Int ?? 0
                days[day] = totals
            }
            return UInt64(complete.count)
        }
    }
}

/// Consommation de Claude Code en haut à droite de l'onglet Claude.
struct ClaudeUsageLabel: View {
    @Environment(ClaudeUsage.self) private var usage

    var body: some View {
        // Se raccourcit quand la place manque : jour et semaine, puis le jour seul, puis l'icône.
        ViewThatFits(in: .horizontal) {
            label(usage.isLoaded ? "\(ClaudeUsage.format(usage.today.total)) auj. · \(ClaudeUsage.format(usage.week.total)) 7 j" : "…")
            label(usage.isLoaded ? "\(ClaudeUsage.format(usage.today.total)) auj." : "…")
            label(nil)
        }
        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
        .foregroundStyle(.primary.opacity(0.55))
        .padding(.horizontal, 6)
        .help(details)
        .onAppear { usage.refresh() }
        .task {
            // Mise à jour tant que l'onglet est affiché.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                usage.refresh()
            }
        }
    }

    private func label(_ text: String?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 9))
            if let text { Text(text).lineLimit(1) }
        }
        .fixedSize()
    }

    private var details: String {
        func line(_ title: String, _ totals: ClaudeUsage.Totals) -> String {
            "\(title) : \(ClaudeUsage.format(totals.total)) tokens — "
                + "\(ClaudeUsage.format(totals.output)) écrits, \(ClaudeUsage.format(totals.input + totals.cacheWrite)) lus, "
                + "\(ClaudeUsage.format(totals.cacheRead)) relus en cache"
        }
        return [line("Aujourd'hui", usage.today), line("7 derniers jours", usage.week)].joined(separator: "\n")
    }
}
