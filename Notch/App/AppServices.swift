import SwiftUI

/// Services partagés par toutes les encoches (un seul exemplaire pour tous les écrans).
@MainActor
struct AppServices {
    let settings: AppSettings
    let alerts: AlertCenter
    let music: MusicController
    let volume: VolumeController
    let calendar: CalendarController
    let clipboard: ClipboardController
    let shelf: ShelfController
    let screenshots: ScreenshotWatcher
    let claudeCode: ClaudeCodeMonitor
    let ask: ClaudeAsk
    let launchAtLogin: LaunchAtLogin
    let systemNotifications: SystemNotificationWatcher

    init() {
        settings = AppSettings()
        alerts = AlertCenter()
        music = MusicController()
        volume = VolumeController()
        calendar = CalendarController()
        clipboard = ClipboardController()
        shelf = ShelfController()
        screenshots = ScreenshotWatcher()
        claudeCode = ClaudeCodeMonitor()
        claudeCode.alerts = alerts
        volume.alerts = alerts
        volume.setReplacesSystemHUD(settings.replaceSystemVolumeHUD)
        ask = ClaudeAsk()
        launchAtLogin = LaunchAtLogin()
        systemNotifications = SystemNotificationWatcher(alerts: alerts, settings: settings)
    }
}

extension View {
    @MainActor
    func environment(_ services: AppServices) -> some View {
        environment(services.settings)
            .environment(services.alerts)
            .environment(services.music)
            .environment(services.volume)
            .environment(services.calendar)
            .environment(services.clipboard)
            .environment(services.shelf)
            .environment(services.screenshots)
            .environment(services.claudeCode)
            .environment(services.ask)
            .environment(services.launchAtLogin)
            .environment(services.systemNotifications)
    }
}
