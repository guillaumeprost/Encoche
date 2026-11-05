import AppKit
import SwiftUI

/// Fenêtre transparente, sans bordure, posée au-dessus de la barre de menus.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        // Présente sur tous les bureaux, mais pas sur ceux des apps en plein écran
        // (pas de `.fullScreenAuxiliary`) : l'encoche s'efface devant une vidéo ou une app plein écran.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Vue SwiftUI de l'encoche qui réagit dès le premier clic : sans ça, l'encoche n'ayant
/// jamais le focus, un premier clic (sur une notification…) servait seulement à l'activer.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
