import AppKit
import SwiftUI

extension NSScreen {
    /// L'écran a une encoche physique (MacBook récents).
    var hasNotch: Bool {
        safeAreaInsets.top > 0 && auxiliaryTopLeftArea != nil && auxiliaryTopRightArea != nil
    }

    /// Taille de l'encoche physique, ou d'une encoche simulée à la hauteur de la barre de menus.
    var notchSize: CGSize {
        ScreenLayout.notchSize(
            frame: frame, visibleFrame: visibleFrame, safeAreaTop: safeAreaInsets.top,
            leftArea: auxiliaryTopLeftArea, rightArea: auxiliaryTopRightArea)
    }
}

extension URL {
    /// Dossier des données d'Encoche (historiques, images…), créé au besoin.
    /// Il garde l'ancien nom de l'app, « Notch », pour ne pas perdre les données existantes.
    static let appSupport: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notch", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
}

/// Lance un outil en ligne de commande hors du fil principal.
enum ProcessRunner {
    struct Output {
        let data: Data
        let status: Int32
        var text: String { String(decoding: data, as: UTF8.self) }
    }

    /// Renvoie sa sortie standard et son code de retour, ou `nil` s'il n'a pas pu être lancé.
    nonisolated static func run(_ path: String, _ arguments: [String]) async -> Output? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
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
                continuation.resume(returning: Output(data: data, status: process.terminationStatus))
            }
        }
    }
}

/// Durées affichées en « minutes:secondes » (minuteur, appel, morceau…).
enum Clock {
    nonisolated static func text(_ seconds: Int) -> String {
        let seconds = max(seconds, 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

extension View {
    /// Menu présenté comme un simple bouton (sans flèche ni fond), à sa taille.
    func plainMenu() -> some View {
        menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    /// Fond Liquid Glass d'un bouton, qui réagit au survol et au clic. Teinté pour une action
    /// principale ; `isShown` à `false` pour un bouton discret qui n'en a qu'au survol.
    @ViewBuilder
    func glassButton(in shape: some Shape, tint: Color? = nil, isShown: Bool = true) -> some View {
        if isShown {
            glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            self
        }
    }
}

/// Petit bouton icône qui active un affichage en direct sous l'encoche (karaoké, Claude).
/// Allumé : fond plein (le verre teinté ne se redessinait pas toujours à la réouverture
/// d'un onglet, et le bouton semblait éteint).
struct LiveLineToggle: View {
    let symbol: String
    let isOn: Bool
    var tint: Color = .accentColor
    /// Atténué quand rien ne peut s'afficher pour l'instant (il reste cliquable).
    var isAvailable = true
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .frame(width: 30, height: 22)
                .background(Capsule().fill(tint).opacity(isOn ? 1 : 0))
                .glassButton(in: Capsule(), isShown: !isOn && hovering)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isAvailable ? 1 : 0.45)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isOn)
        .help(help)
    }
}
