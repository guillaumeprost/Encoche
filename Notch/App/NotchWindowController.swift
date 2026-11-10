import AppKit
import SwiftUI

/// Une encoche sur un écran donné. Chaque écran a la sienne, avec son propre état
/// ouvert/fermé ; la musique, le calendrier et les réglages sont partagés.
@MainActor
final class NotchWindowController {
    private static let panelSize = CGSize(width: 880, height: 280)

    private let viewModel = NotchViewModel()
    private let music: MusicController
    private let calendar: CalendarController
    private let claudeCode: ClaudeCodeMonitor
    private let privacy: PrivacyMonitor
    private let downloads: DownloadMonitor
    private let timer: TimerController
    private let focus: FocusMonitor
    private let calls: CallMonitor
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
    /// Repère du presse-papier de glisser au début d'un clic : un glisser de fichiers démarré
    /// ailleurs (Finder…) le change, et l'encoche s'ouvre alors sur l'Étagère pour le recevoir.
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount

    init(screen: NSScreen, services: AppServices) {
        music = services.music
        calendar = services.calendar
        claudeCode = services.claudeCode
        privacy = services.privacy
        downloads = services.downloads
        timer = services.timer
        focus = services.focus
        calls = services.calls
        settings = services.settings
        alerts = services.alerts
        panel = NotchPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize))

        let root = NotchRootView()
            .environment(viewModel)
            .environment(services)
        let hosting = FirstClickHostingView(rootView: root)
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
        // Le premier écran de la liste est l'écran principal choisi dans Réglages Système.
        viewModel.isPrimaryScreen = screen == NSScreen.screens.first

        // Écran sans encoche : on en simule une, à la hauteur de la barre de menus.
        viewModel.notchSize = screen.notchSize
        viewModel.hasPhysicalNotch = screen.hasNotch

        panel.setFrame(ScreenLayout.topCenter(Self.panelSize, in: screen.frame), display: true)
    }

    // MARK: - Survol

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: mask,
            handler: { [weak self] event in
                let type = event.type
                MainActor.assumeIsolated { self?.handle(type) }
            })
        {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: mask,
            handler: { [weak self] event in
                let type = event.type
                MainActor.assumeIsolated { self?.handle(type) }
                return event
            })
        {
            monitors.append(local)
        }
    }

    /// Zone active en coordonnées écran globales (origine en bas à gauche de l'écran principal).
    private func hotRect() -> NSRect {
        let size = viewModel.shapeSize(showsActivity: currentActivity() != nil, tab: settings.tab)
        let rect = ScreenLayout.topCenter(size, in: screenFrame)
        if viewModel.isOpen {
            // Un peu de tolérance pour ne pas la fermer en frôlant le bord.
            return rect.insetBy(dx: -4, dy: -4)
        }
        // Repliée : seulement le corps noir (sans les petits arrondis du haut), pour ne pas
        // l'ouvrir en passant près d'elle. Elle dépasse en haut : un curseur collé au bord de
        // l'écran est à `maxY`, que `contains` exclut.
        var hot = rect.insetBy(dx: viewModel.topRadius, dy: 0)
        hot.size.height += 2
        return hot
    }

    /// Activités en direct de l'encoche repliée, la plus importante d'abord.
    private func currentActivities() -> [LiveActivity] {
        LiveActivity.active(
            settings: settings, claudeCode: claudeCode, privacy: privacy, downloads: downloads, music: music,
            calendar: calendar, timer: timer, focus: focus, calls: calls
        )
    }

    private func currentActivity() -> LiveActivity? { currentActivities().first }

    /// Repliée, le curseur est sur une activité en direct : un clic ouvre son onglet.
    /// Avec une notification dessous, seule la rangée du haut (celle de l'activité) compte.
    /// La deuxième activité est la petite bulle à droite de l'encoche.
    private func activityUnderMouse() -> LiveActivity? {
        let mouse = NSEvent.mouseLocation
        guard !viewModel.isOpen, !viewModel.isRetracted else { return nil }
        let activities = currentActivities()
        let hot = hotRect()
        if hot.contains(mouse) {
            if viewModel.showsAlert, mouse.y < hot.maxY - viewModel.notchSize.height - 2 { return nil }
            return activities.first
        }
        // Même place que dans NotchRootView : décalée de 6 points à droite de la forme, 4 sous le haut.
        guard activities.count > 1, !viewModel.showsAlert else { return nil }
        let size = viewModel.activityHeight - 8
        let bubble = NSRect(x: hot.maxX + viewModel.topRadius + 6, y: hot.maxY - 2 - 4 - size, width: size, height: size)
        return bubble.insetBy(dx: -8, dy: -6).contains(mouse) ? activities[1] : nil
    }

    /// Repliée, l'encoche ne s'ouvre qu'avec le curseur collé en haut de l'écran, au-dessus d'elle.
    private func openingRect() -> NSRect {
        let hot = hotRect()
        return NSRect(x: hot.minX, y: screenFrame.maxY - 2, width: hot.width, height: 4)
    }

    private func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            if let activity = activityUnderMouse() {
                pendingToggle?.cancel()
                pendingToggle = nil
                settings.tab = activity.tab
                setOpen(true)
                return
            }
            dragStartedInside = viewModel.isOpen && hotRect().contains(NSEvent.mouseLocation)
            dragChangeCount = NSPasteboard(name: .drag).changeCount
        case .leftMouseDragged:
            openForIncomingFiles()
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
        // Repliée, elle ne prend les clics que sur une activité en direct (qui ouvre son onglet) :
        // ailleurs, ils passent à l'app en dessous.
        if !viewModel.isOpen { panel.ignoresMouseEvents = activityUnderMouse() == nil }

        if isFullScreen, !handleFullScreenReveal(mouse) { return }

        // Reste ouverte pendant une saisie, ou tant qu'un glisser parti de l'encoche n'est pas lâché
        // (sinon le fichier qu'on sort de l'étagère disparaîtrait en plein mouvement).
        let inside =
            (viewModel.isOpen ? hotRect() : openingRect()).contains(mouse)
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

    /// Des fichiers glissés depuis une autre app arrivent sur l'encoche : elle s'ouvre tout de
    /// suite sur l'Étagère, qui les reçoit.
    private func openForIncomingFiles() {
        guard !viewModel.isOpen, !viewModel.isRetracted, hotRect().contains(NSEvent.mouseLocation) else { return }
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragChangeCount,
            pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        else { return }
        pendingToggle?.cancel()
        pendingToggle = nil
        settings.tab = .shelf
        setOpen(true)
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
