import SwiftUI

/// Services partagés par toutes les encoches (un seul exemplaire pour tous les écrans).
@MainActor
struct AppServices {
    let settings: AppSettings
    let alerts: AlertCenter
    let hud: HUDCenter
    let battery: BatteryMonitor
    let brightness: BrightnessController
    let privacy: PrivacyMonitor
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
    let bannerSuppressor: BannerSuppressor

    init() {
        settings = AppSettings()
        alerts = AlertCenter()
        hud = HUDCenter()
        battery = BatteryMonitor()
        battery.hud = hud
        brightness = BrightnessController()
        brightness.hud = hud
        privacy = PrivacyMonitor()
        music = MusicController()
        volume = VolumeController()
        calendar = CalendarController()
        clipboard = ClipboardController()
        shelf = ShelfController()
        screenshots = ScreenshotWatcher()
        claudeCode = ClaudeCodeMonitor()
        claudeCode.alerts = alerts
        volume.alerts = alerts
        volume.hud = hud
        volume.brightness = brightness
        calendar.alerts = alerts
        calendar.startMeetingReminders()
        volume.setReplacesSystemHUD(settings.replaceSystemVolumeHUD)
        ask = ClaudeAsk()
        launchAtLogin = LaunchAtLogin()
        systemNotifications = SystemNotificationWatcher(alerts: alerts, settings: settings)

        // Bannières de macOS fermées tant que Notch les relaie : seulement si le relais marche,
        // pour ne jamais perdre une notification.
        bannerSuppressor = BannerSuppressor()
        let settings = settings, watcher = systemNotifications
        bannerSuppressor.isEnabled = {
            settings.hideSystemBanners && settings.mirrorSystemNotifications && watcher.access == .granted
        }
        bannerSuppressor.beforeClosing = { watcher.pollNow() }
        let alertCenter = alerts
        bannerSuppressor.onUnreadBanner = { appName, title, body in
            guard !alertCenter.hasRecent(title: title) else { return }
            let bundleID = AppDirectory.bundleID(forName: appName)
            alertCenter.post(NotchAlert(
                icon: bundleID.map { .app(bundleID: $0) } ?? .symbol("bell.fill", .gray),
                source: appName,
                title: title,
                body: body,
                action: bundleID.map { .openApp(bundleID: $0) }
            ))
        }
        bannerSuppressor.start()
    }
}

extension View {
    @MainActor
    func environment(_ services: AppServices) -> some View {
        environment(services.settings)
            .environment(services.alerts)
            .environment(services.hud)
            .environment(services.battery)
            .environment(services.brightness)
            .environment(services.privacy)
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
