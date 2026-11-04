import AppKit

/// Détecte les écrans sur lesquels une app est en plein écran.
///
/// macOS affiche nos fenêtres (niveau barre de menus) même sur les bureaux plein écran,
/// donc on le détecte nous-mêmes : en plein écran, une fenêtre normale (niveau 0)
/// couvre tout l'écran, barre de menus comprise — ce qu'une fenêtre simplement
/// agrandie ne fait jamais. Les bornes des fenêtres sont lisibles sans permission.
@MainActor
final class FullScreenDetector {
    private let onChange: (Set<CGDirectDisplayID>) -> Void
    private var current: Set<CGDirectDisplayID> = []
    private var timer: Timer?

    init(onChange: @escaping (Set<CGDirectDisplayID>) -> Void) {
        self.onChange = onChange

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkSoon() }
            }
        }
        // Filet de sécurité : entrée en plein écran sans changement d'app active, etc.
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        check()
    }

    /// Vérifie tout de suite, puis après l'animation de passage en plein écran.
    private func checkSoon() {
        check()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            self?.check()
        }
    }

    func check() {
        let detected = Self.fullScreenDisplays()
        guard detected != current else { return }
        current = detected
        onChange(detected)
    }

    private static func fullScreenDisplays() -> Set<CGDirectDisplayID> {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let covering: [CGRect] = windows.compactMap { window in
            guard window[kCGWindowLayer as String] as? Int == 0,
                  window[kCGWindowOwnerPID as String] as? pid_t != ownPID,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { return nil }
            return bounds
        }

        var result = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            let frame = screen.quartzFrame
            if covering.contains(where: { $0.insetBy(dx: -1, dy: -1).contains(frame) }) {
                result.insert(id)
            }
        }
        return result
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// Cadre de l'écran en coordonnées Quartz (origine en haut à gauche de l'écran principal),
    /// celles qu'utilise CGWindowList.
    var quartzFrame: CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? frame.height
        return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}
