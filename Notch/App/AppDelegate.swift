import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var shared: AppDelegate?

    private var screenManager: NotchScreenManager?
    private var lockScreen: LockScreenController?
    private var screenSaver: ScreenSaverOverlay?
    private var settingsWindow: SettingsWindowController?
    /// Empêche « App Nap » : macOS suspendrait sinon les minuteurs d'une app sans fenêtre
    /// au premier plan, et le presse-papier ou les notifications ne seraient plus suivis.
    /// Le Mac peut toujours se mettre en veille normalement.
    private var activity: NSObjectProtocol?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        shared = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Lancée pour les tests unitaires : pas d'encoche, de hooks ni de surveillance.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Suivi du presse-papier, des notifications et de la musique"
        )
        let services = AppServices()
        let settingsWindow = SettingsWindowController(services: services)
        services.settings.openSettings = { settingsWindow.show() }
        self.settingsWindow = settingsWindow
        screenManager = NotchScreenManager(services: services)
        lockScreen = LockScreenController(services: services)
        screenSaver = ScreenSaverOverlay(services: services)
    }
}
