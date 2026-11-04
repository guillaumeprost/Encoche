import AppKit

/// Maintient une encoche par écran connecté, suit les branchements/débranchements
/// ou changements de résolution, et masque l'encoche des écrans en plein écran.
@MainActor
final class NotchScreenManager {
    private let services: AppServices
    private var controllers: [CGDirectDisplayID: NotchWindowController] = [:]
    private var fullScreenDisplays: Set<CGDirectDisplayID> = []
    private var detector: FullScreenDetector?
    private var dragWatcher: FileDragWatcher?

    init(services: AppServices) {
        self.services = services

        syncScreens()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncScreens() }
        }

        // Un fichier pris n'importe où : toutes les encoches s'ouvrent pour le recevoir.
        dragWatcher = FileDragWatcher(
            onStart: { [weak self] in self?.controllers.values.forEach { $0.beginFileDrag() } },
            onEnd: { [weak self] in self?.controllers.values.forEach { $0.endFileDrag() } }
        )

        detector = FullScreenDetector { [weak self] displays in
            self?.fullScreenDisplays = displays
            self?.applyFullScreenState()
        }
    }

    private func syncScreens() {
        var current: [CGDirectDisplayID: NSScreen] = [:]
        for screen in NSScreen.screens {
            if let id = screen.displayID { current[id] = screen }
        }

        for (id, controller) in controllers where current[id] == nil {
            controller.invalidate()
            controllers[id] = nil
        }

        for (id, screen) in current {
            if let controller = controllers[id] {
                controller.update(screen: screen)
            } else {
                controllers[id] = NotchWindowController(screen: screen, services: services)
            }
        }

        detector?.check()
        applyFullScreenState()
    }

    private func applyFullScreenState() {
        for (id, controller) in controllers {
            controller.setFullScreen(fullScreenDisplays.contains(id))
        }
    }
}
