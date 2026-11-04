import AppKit

/// Maintient une encoche par écran connecté, et suit les branchements/débranchements
/// ou changements de résolution.
@MainActor
final class NotchScreenManager {
    private let settings: AppSettings
    private let music: MusicController
    private let calendar: CalendarController
    private var controllers: [CGDirectDisplayID: NotchWindowController] = [:]

    init(settings: AppSettings, music: MusicController, calendar: CalendarController) {
        self.settings = settings
        self.music = music
        self.calendar = calendar

        syncScreens()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncScreens() }
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
                controllers[id] = NotchWindowController(
                    screen: screen, settings: settings, music: music, calendar: calendar
                )
            }
        }
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
