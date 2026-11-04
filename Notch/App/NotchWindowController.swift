import AppKit
import SwiftUI

@MainActor
final class NotchWindowController {
    private static let panelSize = CGSize(width: 640, height: 260)

    private let viewModel: NotchViewModel
    private let music: MusicController
    private let panel: NotchPanel
    private var monitors: [Any] = []
    private var pendingToggle: Task<Void, Never>?
    private var screenFrame: NSRect = .zero

    init(viewModel: NotchViewModel, music: MusicController) {
        self.viewModel = viewModel
        self.music = music
        panel = NotchPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize))

        let root = NotchRootView()
            .environment(viewModel)
            .environment(music)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting

        reposition()
        panel.orderFrontRegardless()
        installMonitors()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    // MARK: - Placement

    private func reposition() {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
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
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            viewModel.notchSize = CGSize(width: 190, height: max(menuBarHeight, 24))
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

    /// Zone active en coordonnées écran (origine en bas à gauche).
    private func hotRect() -> NSRect {
        let size = viewModel.shapeSize(showsActivity: music.showsActivity)
        let rect = NSRect(x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height,
                          width: size.width, height: size.height)
        // Un peu de tolérance quand c'est replié, pour attraper la souris facilement.
        return viewModel.isOpen ? rect.insetBy(dx: -4, dy: -4) : rect.insetBy(dx: -8, dy: -2)
    }

    private func handleMouse() {
        let inside = hotRect().contains(NSEvent.mouseLocation)
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
        panel.ignoresMouseEvents = !open
        if open { music.refreshPosition() }
    }
}
