import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var shared: AppDelegate?

    private var screenManager: NotchScreenManager?
    private var settingsWindow: SettingsWindowController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        shared = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let services = AppServices()
        let settingsWindow = SettingsWindowController(services: services)
        services.settings.openSettings = { settingsWindow.show() }
        self.settingsWindow = settingsWindow
        screenManager = NotchScreenManager(services: services)
    }
}
