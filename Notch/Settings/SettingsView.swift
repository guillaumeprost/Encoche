import AppKit
import SwiftUI

/// Fenêtre de réglages : toutes les options, et l'état de chaque autorisation macOS
/// avec un bouton pour la régler.
@MainActor
final class SettingsWindowController {
    private let services: AppServices
    private var window: NSWindow?

    init(services: AppServices) {
        self.services = services
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView().environment(services))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Réglages d’Encoche"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 520, height: 640))
            window.center()
            self.window = window
        }
        // App sans icône dans le Dock : il faut l'activer pour passer la fenêtre devant.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LaunchAtLogin.self) private var launchAtLogin
    @Environment(SystemNotificationWatcher.self) private var notifications
    @Environment(VolumeController.self) private var volume
    @Environment(CalendarController.self) private var calendar
    @Environment(ClaudeCodeMonitor.self) private var claudeCode
    @Environment(ClaudeAsk.self) private var ask

    var body: some View {
        @Bindable var settings = settings
        // Certaines autorisations (Accessibilité) ne préviennent pas quand elles changent :
        // on réévalue l'écran toutes les 2 s tant que la fenêtre est ouverte.
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            Form {
                Section("Général") {
                    if launchAtLogin.isInstalledCopy {
                        Toggle("Ouvrir Encoche au démarrage du Mac", isOn: Binding(
                            get: { launchAtLogin.isEnabled }, set: { launchAtLogin.set($0) }
                        ))
                    } else {
                        Text("Ouverture au démarrage : seulement pour la copie installée dans Applications.")
                            .foregroundStyle(.secondary)
                    }
                    Picker("Encoche ouverte", selection: $settings.notchStyle) {
                        ForEach(AppSettings.NotchStyle.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section {
                    Toggle("Afficher les notifications macOS dans l'encoche", isOn: $settings.mirrorSystemNotifications)
                    Toggle("Masquer les bannières de macOS", isOn: $settings.hideSystemBanners)
                        .disabled(!settings.mirrorSystemNotifications)
                    Toggle("Seulement sur l'écran principal", isOn: $settings.notificationsOnPrimaryScreenOnly)
                    PermissionRow(
                        title: "Accès complet au disque",
                        detail: "Pour lire les notifications des autres apps.",
                        granted: notifications.access == .granted,
                        action: notifications.openPrivacySettings
                    )
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Les bannières sont masquées seulement si Encoche peut lire les notifications : rien ne se perd.")
                }

                Section {
                    Toggle("Afficher sur l'écran de verrouillage", isOn: $settings.showOnLockScreen)
                    Toggle("Lecteur de musique", isOn: $settings.lockScreenMusic)
                        .disabled(!settings.showOnLockScreen)
                    Picker("Son de verrouillage", selection: $settings.lockSound) {
                        ForEach(LockSound.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Son de déverrouillage", selection: $settings.unlockSound) {
                        ForEach(LockSound.allCases) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("Écran de verrouillage")
                } footer: {
                    Text("Un cadenas dans l'encoche et la musique en cours quand le Mac est verrouillé.")
                }
                .onChange(of: settings.lockSound) { settings.lockSound.play() }
                .onChange(of: settings.unlockSound) { settings.unlockSound.play() }

                Section {
                    Toggle("Claude Code au travail", isOn: $settings.showClaudeActivity)
                    Toggle("Téléchargements", isOn: $settings.showDownloadActivity)
                    Toggle("Réunion dans moins de 10 minutes", isOn: $settings.showMeetingActivity)
                    Toggle("Mode Concentration", isOn: $settings.showFocusActivity)
                    Toggle("Appareils Bluetooth (AirPods…)", isOn: $settings.showBluetoothActivity)
                } header: {
                    Text("Activités en direct")
                } footer: {
                    Text("Affichées autour de l'encoche repliée, comme la musique, la caméra et le micro.")
                }

                Section {
                    Toggle("Remplacer les indicateurs de volume et de luminosité", isOn: Binding(
                        get: { settings.replaceSystemVolumeHUD },
                        set: {
                            settings.replaceSystemVolumeHUD = $0
                            volume.setReplacesSystemHUD($0)
                        }
                    ))
                    PermissionRow(
                        title: "Accessibilité",
                        detail: "Pour les touches volume / luminosité et masquer les bannières.",
                        granted: AXIsProcessTrusted(),
                        action: volume.requestAccessibility
                    )
                } header: {
                    Text("Volume et luminosité")
                }

                Section("Calendrier") {
                    PermissionRow(
                        title: "Accès au calendrier",
                        detail: "Agenda du jour et rappels de réunion.",
                        granted: calendar.access == .granted,
                        action: calendar.access == .notDetermined ? calendar.requestAccess : calendar.openPrivacySettings
                    )
                }

                Section {
                    LabeledContent("Suivi des sessions") {
                        if claudeCode.hooksInstalled {
                            Button("Désinstaller les hooks", role: .destructive) { claudeCode.uninstallHooks() }
                        } else {
                            Button("Installer les hooks") { claudeCode.installHooks() }
                        }
                    }
                    if let error = claudeCode.hooksError {
                        Text(error).foregroundStyle(.orange)
                    }
                    LabeledContent("Questions rapides") {
                        if ask.cliURL == nil {
                            StatusLabel(granted: false, text: "Claude Code introuvable")
                        } else if ask.needsLogin {
                            StatusLabel(granted: false, text: "Lance `claude` puis /login")
                        } else {
                            StatusLabel(granted: true, text: "Via ton abonnement")
                        }
                    }
                } header: {
                    Text("Claude")
                }

                Section("À propos") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    Button("Quitter Encoche", role: .destructive) { NSApp.terminate(nil) }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 480, minHeight: 560)
    }
}

/// Une autorisation macOS : son état, et un bouton pour la régler si elle manque.
private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        LabeledContent {
            if granted {
                StatusLabel(granted: true, text: "Autorisé")
            } else {
                Button("Autoriser…", action: action)
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }
}

private struct StatusLabel: View {
    let granted: Bool
    let text: String

    var body: some View {
        Label(text, systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(granted ? .green : .orange)
    }
}
