import AppKit
import Observation
import SwiftUI

/// Pilote la maison par l'app Raccourcis.
///
/// macOS ne donne pas accès à HomeKit aux apps Mac : on passe par les raccourcis du dossier
/// « Encoche » de l'app Raccourcis (allumer une lampe, lancer une scène…), listés et lancés
/// avec la commande `shortcuts`. Encoche ne voit donc pas l'état des appareils.
@Observable
@MainActor
final class HomeShortcuts {
    static let folderName = "Encoche"
    private static let tool = "/usr/bin/shortcuts"

    struct Shortcut: Identifiable, Hashable {
        let name: String
        var id: String { name }
        var style: HomeShortcutStyle { HomeShortcutStyle(name: name) }
    }

    enum RunState { case running, done, failed }

    private(set) var shortcuts: [Shortcut] = []
    /// Le dossier « Encoche » existe dans Raccourcis.
    private(set) var hasFolder = true
    private(set) var isLoaded = false
    private(set) var states: [String: RunState] = [:]

    @ObservationIgnored private var isRefreshing = false

    /// Relit le dossier (à chaque ouverture de l'onglet : l'utilisateur a pu en ajouter).
    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            defer { isRefreshing = false }
            // Sans dossier, `shortcuts list --folder-name` liste *tous* les raccourcis :
            // on vérifie d'abord qu'il existe.
            let folders = await Self.execute(["list", "--folders"])?.lines ?? []
            let exists = folders.contains(Self.folderName)
            let names = exists ? (await Self.execute(["list", "--folder-name", Self.folderName])?.lines ?? []) : []
            hasFolder = exists
            let updated = names.map { Shortcut(name: $0) }
            if updated != shortcuts { shortcuts = updated }
            isLoaded = true
        }
    }

    func run(_ shortcut: Shortcut) {
        guard states[shortcut.name] != .running else { return }
        states[shortcut.name] = .running
        Task {
            let ok = await Self.execute(["run", shortcut.name]) != nil
            states[shortcut.name] = ok ? .done : .failed
            try? await Task.sleep(for: .seconds(1.5))
            if states[shortcut.name] != .running { states[shortcut.name] = nil }
        }
    }

    func openShortcutsApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Lance `shortcuts` hors du fil principal. Renvoie sa sortie, ou `nil` en cas d'échec.
    private nonisolated static func execute(_ arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: tool)
                process.arguments = arguments
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: String(decoding: data, as: UTF8.self))
            }
        }
    }
}

/// Icône et couleur devinées d'après le nom du raccourci (« Lumière salon », « Scène soirée »…).
struct HomeShortcutStyle {
    let symbol: String
    let tint: Color

    private static let rules: [(keywords: [String], symbol: String, tint: Color)] = [
        (["éteindre", "eteindre", "off", "couper"], "power", .gray),
        (["lumière", "lumiere", "lampe", "chevet", "plafonnier", "guirlande", "éclairage", "light"], "lightbulb.fill", .yellow),
        (["prise", "plug"], "poweroutlet.type.f.fill", .green),
        (["volet", "store", "rideau"], "blinds.horizontal.closed", .blue),
        (["chauffage", "thermostat", "radiateur", "clim", "température"], "thermometer.medium", .orange),
        (["porte", "serrure", "verrou", "lock"], "lock.fill", .blue),
        (["garage"], "door.garage.closed", .blue),
        (["tv", "télé", "tele"], "tv.fill", .indigo),
        (["musique", "enceinte", "homepod", "music"], "hifispeaker.fill", .pink),
        (["moustique"], "ant.fill", .green),
        (["nuit", "dodo", "coucher", "soir"], "moon.fill", .indigo),
        (["matin", "réveil", "reveil", "jour"], "sun.max.fill", .orange),
        (["départ", "depart", "partir", "absent"], "figure.walk.departure", .teal),
        (["arrivée", "arrivee", "retour", "maison"], "house.fill", .orange),
        (["film", "cinéma", "cinema"], "film.fill", .purple),
        (["aspirateur", "nettoie", "ménage", "menage"], "fan.fill", .teal),
    ]

    init(name: String) {
        let lowered = name.lowercased()
        let match = Self.rules.first { rule in rule.keywords.contains { lowered.contains($0) } }
        symbol = match?.symbol ?? "sparkles"
        tint = match?.tint ?? .accentColor
    }
}

private extension String {
    var lines: [String] {
        split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
