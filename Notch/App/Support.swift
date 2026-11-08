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
}
