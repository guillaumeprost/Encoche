import AppKit

/// Détecte qu'un fichier est en train d'être glissé, n'importe où sur l'écran.
///
/// Pendant un glisser, macOS ne transmet plus les mouvements de souris aux autres apps :
/// on ne peut pas se fier aux événements. On regarde donc, tant que le bouton est enfoncé,
/// si le presse-papier de glisser a changé depuis le clic et s'il contient des fichiers.
@MainActor
final class FileDragWatcher {
    private let onStart: () -> Void
    private let onEnd: () -> Void

    private var monitor: Any?
    private var timer: Timer?
    private var changeCountAtMouseDown = 0
    private var isDragging = false

    init(onStart: @escaping () -> Void, onEnd: @escaping () -> Void) {
        self.onStart = onStart
        self.onEnd = onEnd

        // Le clic, lui, est bien reçu avant que le glisser ne commence.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown() }
        }
    }

    private func mouseDown() {
        changeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        let buttonDown = NSEvent.pressedMouseButtons & 1 != 0

        if !buttonDown {
            timer?.invalidate()
            timer = nil
            if isDragging {
                isDragging = false
                onEnd()
            }
            return
        }

        guard !isDragging else { return }
        let pasteboard = NSPasteboard(name: .drag)
        if pasteboard.changeCount != changeCountAtMouseDown,
           pasteboard.types?.contains(.fileURL) == true {
            isDragging = true
            onStart()
        }
    }
}
