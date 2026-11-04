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
    private let settings: AppSettings
    private let alerts: AlertCenter
    private let panel: NotchPanel
    private var monitors: [Any] = []
    private var pendingToggle: Task<Void, Never>?
    private var screenFrame: NSRect = .zero
    /// Une app est en plein écran sur cet écran : l'encoche se range avec la barre de menus.
    private var isFullScreen = false
    private var pendingRetract: Task<Void, Never>?
    /// Un glisser parti de l'encoche (fichier sorti de l'étagère) : elle reste ouverte jusqu'au lâcher.
    private var dragStartedInside = false

    init(screen: NSScreen, services: AppServices) {
        music = services.music
        calendar = services.calendar
        claudeCode = services.claudeCode
        settings = services.settings
        alerts = services.alerts
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

    /// En plein écran, l'encoche se range au-dessus de l'écran comme la barre de menus,
    /// et redescend avec elle quand le curseur touche le haut de l'écran.
    func setFullScreen(_ fullScreen: Bool) {
        guard fullScreen != isFullScreen else { return }
        isFullScreen = fullScreen
        pendingToggle?.cancel()
        pendingToggle = nil
        pendingRetract?.cancel()
        pendingRetract = nil
        if fullScreen, viewModel.isOpen { setOpen(false) }
        viewModel.isRetracted = fullScreen
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
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handle(type) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handle(type) }
            return event
        }) {
            monitors.append(local)
        }
    }

    /// Zone active en coordonnées écran globales (origine en bas à gauche de l'écran principal).
    private func hotRect() -> NSRect {
        let size = viewModel.shapeSize(
            showsActivity: claudeCode.needsAttention || music.showsActivity,
            extraHeight: settings.tab == .home ? NotchViewModel.homeExtraHeight : 0
        )
        let rect = NSRect(x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height,
                          width: size.width, height: size.height)
        // Un peu de tolérance quand c'est replié, pour attraper la souris facilement.
        return viewModel.isOpen ? rect.insetBy(dx: -4, dy: -4) : rect.insetBy(dx: -8, dy: -2)
    }

    private func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            dragStartedInside = viewModel.isOpen && hotRect().contains(NSEvent.mouseLocation)
        case .leftMouseUp:
            dragStartedInside = false
        default:
            break
        }
        handleMouse()
    }

    private func handleMouse() {
        let mouse = NSEvent.mouseLocation

        // Notification affichée : le survol la garde à l'écran, le clic l'ouvre ;
        // on n'ouvre pas l'encoche par-dessus.
        if viewModel.showsAlert, !viewModel.isOpen {
            let over = hotRect().contains(mouse)
            alerts.setHovering(over, from: ObjectIdentifier(self))
            panel.ignoresMouseEvents = !over
            pendingToggle?.cancel()
            pendingToggle = nil
            return
        }
        alerts.setHovering(false, from: ObjectIdentifier(self))
        if !viewModel.isOpen { panel.ignoresMouseEvents = true }

        if isFullScreen, !handleFullScreenReveal(mouse) { return }

        // Reste ouverte pendant une saisie, ou tant qu'un glisser parti de l'encoche n'est pas lâché
        // (sinon le fichier qu'on sort de l'étagère disparaîtrait en plein mouvement).
        let inside = hotRect().contains(mouse)
            || (viewModel.isOpen && viewModel.holdOpen)
            || (viewModel.isOpen && dragStartedInside)
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

    /// Plein écran : sortie/rentrée de l'encoche avec la barre de menus.
    /// Renvoie `true` si l'encoche est sortie et doit gérer le survol normalement.
    private func handleFullScreenReveal(_ mouse: NSPoint) -> Bool {
        let onThisScreen = mouse.x >= screenFrame.minX && mouse.x < screenFrame.maxX
        // Hauteur de la barre de menus qui descend (au moins celle de l'encoche).
        let menuBarZone = max(viewModel.notchSize.height, 24) + 6

        if viewModel.isRetracted {
            // Le curseur touche le haut de l'écran : la barre de menus descend, l'encoche aussi.
            if onThisScreen, mouse.y >= screenFrame.maxY - 1 {
                viewModel.isRetracted = false
            }
            return false
        }

        let nearTop = onThisScreen && mouse.y >= screenFrame.maxY - menuBarZone
        if nearTop || viewModel.isOpen || hotRect().contains(mouse) {
            pendingRetract?.cancel()
            pendingRetract = nil
        } else if pendingRetract == nil {
            // Le curseur redescend : on remonte avec la barre de menus.
            pendingRetract = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, let self else { return }
                self.pendingRetract = nil
                if self.isFullScreen, !self.viewModel.isOpen { self.viewModel.isRetracted = true }
            }
        }
        return true
    }

    private func setOpen(_ open: Bool) {
        viewModel.isOpen = open
        if !open { viewModel.holdOpen = false }
        panel.ignoresMouseEvents = !open
        if open {
            settings.refreshSystemGlassTint()
            music.refreshPosition()
            calendar.selectToday()
        }
    }
}
