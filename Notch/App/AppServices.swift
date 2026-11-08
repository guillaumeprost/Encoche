import EventKit
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
    let downloads: DownloadMonitor
    let bluetooth: BluetoothMonitor
    let focus: FocusMonitor
    let sidecar: SidecarController
    let meeting: MeetingController
    let calls: CallMonitor
    let timer: TimerController
    let music: MusicController
    let musicExtras: MusicExtras
    let volume: VolumeController
    let calendar: CalendarController
    let reminders: RemindersController
    let clipboard: ClipboardController
    let shelf: ShelfController
    let screenshots: ScreenshotWatcher
    let home: HomeShortcuts
    let claudeCode: ClaudeCodeMonitor
    let ask: ClaudeAsk
    let claudeUsage: ClaudeUsage
    let claudeQuota: ClaudeQuota
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
        downloads = DownloadMonitor()
        bluetooth = BluetoothMonitor()
        bluetooth.hud = hud
        let appSettings = settings
        bluetooth.isEnabled = { appSettings.showBluetoothActivity }
        bluetooth.start()
        focus = FocusMonitor()
        sidecar = SidecarController()
        meeting = MeetingController()
        meeting.privacy = privacy
        calls = CallMonitor()
        calls.alerts = alerts
        calls.privacy = privacy
        timer = TimerController()
        music = MusicController()
        musicExtras = MusicExtras(music: music)
        volume = VolumeController()
        // Une seule base EventKit pour le calendrier et les rappels.
        let eventStore = EKEventStore()
        calendar = CalendarController(store: eventStore)
        reminders = RemindersController(store: eventStore)
        clipboard = ClipboardController()
        shelf = ShelfController()
        screenshots = ScreenshotWatcher()
        home = HomeShortcuts()
        claudeCode = ClaudeCodeMonitor()
        claudeCode.alerts = alerts
        timer.alerts = alerts
        volume.alerts = alerts
        volume.hud = hud
        volume.brightness = brightness
        calendar.alerts = alerts
        calendar.startMeetingReminders()
        volume.setReplacesSystemHUD(settings.replaceSystemVolumeHUD)
        ask = ClaudeAsk()
        ask.alerts = alerts
        // Un clic sur la réponse : l'encoche s'ouvrira sur l'onglet Claude, en question rapide.
        ask.openAnswer = { [weak ask] in
            appSettings.tab = .claude
            ask?.target = .quickQuestion
        }
        claudeUsage = ClaudeUsage()
        claudeQuota = ClaudeQuota()
        launchAtLogin = LaunchAtLogin()
        systemNotifications = SystemNotificationWatcher(alerts: alerts, settings: settings)

        // Bannières de macOS fermées tant qu'Encoche les relaie : lues dans la base des
        // notifications, sinon dans la bannière elle-même (Accessibilité).
        bannerSuppressor = BannerSuppressor()
        let settings = settings
        let watcher = systemNotifications
        bannerSuppressor.isEnabled = { settings.hideSystemBanners && settings.mirrorSystemNotifications }
        bannerSuppressor.canReadDatabase = { watcher.access == .granted }
        bannerSuppressor.beforeClosing = { watcher.pollNow() }
        let callMonitor = calls
        bannerSuppressor.onCallAlerts = { callMonitor.update($0) }
        let alertCenter = alerts
        bannerSuppressor.onUnreadBanner = { appName, title, body in
            guard !alertCenter.hasRecent(title: title) else { return }
            let bundleID = AppDirectory.bundleID(forName: appName)
            alertCenter.post(
                NotchAlert(
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
            .environment(services.downloads)
            .environment(services.bluetooth)
            .environment(services.focus)
            .environment(services.sidecar)
            .environment(services.meeting)
            .environment(services.calls)
            .environment(services.timer)
            .environment(services.music)
            .environment(services.musicExtras)
            .environment(services.volume)
            .environment(services.calendar)
            .environment(services.reminders)
            .environment(services.clipboard)
            .environment(services.shelf)
            .environment(services.screenshots)
            .environment(services.home)
            .environment(services.claudeCode)
            .environment(services.ask)
            .environment(services.claudeUsage)
            .environment(services.claudeQuota)
            .environment(services.launchAtLogin)
            .environment(services.systemNotifications)
    }
}
