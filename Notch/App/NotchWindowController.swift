import AppKit
import SwiftUI

/// Une encoche sur un écran donné. Chaque écran a la sienne, avec son propre état
/// ouvert/fermé ; la musique, le calendrier et les réglages sont partagés.
@MainActor
final class NotchWindowController {
    private static let panelSize = CGSize(width: 780, height: 280)

    private let viewModel = NotchViewModel()
    private let music: MusicController
    private let calendar: CalendarController
    private let claudeCode: ClaudeCodeMonitor
    private let panel: NotchPanel
    private var monitors: [Any] = []
    private var pendingToggle: Task<Void, Never>?
    private var screenFrame: NSRect = .zero

    init(screen: NSScreen, services: AppServices) {
        music = services.music
        calendar = services.calendar
        claudeCode = services.claudeCode
        panel = NotchPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize))

        let root = NotchRootView()
            .environment(viewModel)
            .environment(services)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting

        update(screen: screen)
        panel.orderFrontRegardless()
        installMonitors()

        // Clic dans une autre app : on relâche la saisie et on referme si la souris est sortie.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.viewModel.holdOpen = false
                self?.handleMouse()
            }
        }
    }

    /// Retire l'encoche (écran débranché).
    func invalidate() {
        pendingToggle?.cancel()
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        panel.orderOut(nil)
        panel.close()
    }

    // MARK: - Placement

    func update(screen: NSScreen) {
        screenFrame = screen.frame

        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            viewModel.notchSize = CGSize(
                width: screen.frame.width - left.width - right.width,
                height: screen.safeAreaInsets.top
            )
            viewModel.hasPhysicalNotch = true
        } else {
            // Écran sans encoche : on en simule une, à la hauteur de la barre de menus.
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            viewModel.notchSize = CGSize(width: 190, height: menuBarHeight > 0 ? menuBarHeight : 24)
            viewModel.hasPhysicalNotch = false
        }

        let size = Self.panelSize
        panel.setFrame(
            NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                   width: size.width, height: size.height),
            display: true
        )
    }

    // MARK: - Survol

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMouse() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleMouse() }
            return event
        }) {
            monitors.append(local)
        }
    }

    /// Zone active en coordonnées écran globales (origine en bas à gauche de l'écran principal).
    private func hotRect() -> NSRect {
        let size = viewModel.shapeSize(showsActivity: claudeCode.needsAttention || music.showsActivity)
        let rect = NSRect(x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height,
                          width: size.width, height: size.height)
        // Un peu de tolérance quand c'est replié, pour attraper la souris facilement.
        return viewModel.isOpen ? rect.insetBy(dx: -4, dy: -4) : rect.insetBy(dx: -8, dy: -2)
    }

    private func handleMouse() {
        let inside = hotRect().contains(NSEvent.mouseLocation) || (viewModel.isOpen && viewModel.holdOpen)
        if inside == viewModel.isOpen {
            pendingToggle?.cancel()
            pendingToggle = nil
            return
        }
        guard pendingToggle == nil else { return }

        let delay: Duration = inside ? .milliseconds(120) : .milliseconds(250)
        pendingToggle = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.pendingToggle = nil
            self.setOpen(inside)
        }
    }

    private func setOpen(_ open: Bool) {
        viewModel.isOpen = open
        if !open { viewModel.holdOpen = false }
        panel.ignoresMouseEvents = !open
        if open {
            music.refreshPosition()
            calendar.selectToday()
        }
    }
}
