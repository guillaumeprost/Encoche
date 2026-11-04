import SwiftUI

struct NotchRootView: View {
    @Environment(NotchViewModel.self) private var vm
    @Environment(AppSettings.self) private var settings
    @Environment(MusicController.self) private var music
    @Environment(ClaudeCodeMonitor.self) private var claudeCode
    @Environment(LaunchAtLogin.self) private var launchAtLogin
    @Environment(AlertCenter.self) private var alerts
    @Environment(SystemNotificationWatcher.self) private var systemNotifications
    /// Apparence du Mac (clair / sombre).
    @Environment(\.colorScheme) private var systemColorScheme

    private let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    private let tabTransition = AnyTransition.opacity.combined(with: .scale(scale: 0.97))

    var body: some View {
        let size = vm.shapeSize(
            showsActivity: showsActivity,
            extraHeight: settings.tab == .home ? NotchViewModel.homeExtraHeight : 0
        )
        let shape = NotchShape(topRadius: vm.topRadius, bottomRadius: vm.bottomRadius)

        ZStack(alignment: .top) {
            background(shape)

            if vm.isOpen {
                VStack(spacing: 0) {
                    TopBar()
                        .frame(height: vm.notchSize.height)
                        .padding(.horizontal, 18 + vm.topRadius)

                    ZStack {
                        switch settings.tab {
                        case .home: HomeTab().transition(tabTransition)
                        case .clipboard: ClipboardView().transition(tabTransition)
                        case .claude: ClaudeTab().transition(tabTransition)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 18)
                    .padding(.horizontal, 24 + vm.topRadius)
                    .animation(.snappy(duration: 0.25), value: settings.tab)
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top))
                        .animation(spring.delay(0.06)),
                    removal: .opacity.animation(.easeOut(duration: 0.12))
                ))
            } else if vm.showsAlert, let alert = alerts.current {
                VStack(spacing: 0) {
                    Color.clear.frame(height: vm.notchSize.height)
                    AlertBannerView(alert: alert)
                        .padding(.horizontal, 16 + vm.topRadius)
                        .padding(.top, 6)
                        .padding(.bottom, 12)
                        .frame(maxHeight: .infinity)
                }
                .onTapGesture { alerts.activate() }
                .id(alert.id)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.9, anchor: .top)).animation(spring.delay(0.08)),
                    removal: .opacity.animation(.easeOut(duration: 0.12))
                ))
            } else if claudeCode.needsAttention {
                CollapsedClaudeView(slotWidth: vm.activitySlotWidth)
                    .padding(.horizontal, vm.topRadius)
                    .frame(height: vm.notchSize.height)
                    .transition(.opacity)
            } else if music.showsActivity {
                CollapsedMusicView(slotWidth: vm.activitySlotWidth)
                    .padding(.horizontal, vm.topRadius)
                    .frame(height: vm.notchSize.height)
                    .transition(.opacity)
            }
        }
        // En verre, le contenu suit l'apparence du Mac ; sur fond noir (repliée, ou verre
        // désactivé), il reste en style sombre pour rester lisible.
        .environment(\.colorScheme, glassActive ? systemColorScheme : .dark)
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        .shadow(color: .black.opacity(vm.isOpen || vm.showsAlert ? 0.35 : 0), radius: 18, y: 8)
        .contextMenu {
            Toggle("Liquid Glass", isOn: Binding(get: { settings.useGlass }, set: { settings.useGlass = $0 }))
            if launchAtLogin.isInstalledCopy {
                Toggle("Ouvrir au démarrage", isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.set($0) }))
            }
            Toggle("Notifications macOS", isOn: Binding(
                get: { settings.mirrorSystemNotifications },
                set: { settings.mirrorSystemNotifications = $0 }
            ))
            if systemNotifications.access == .denied {
                Button("Autoriser les notifications macOS…") { systemNotifications.openPrivacySettings() }
            }
            Divider()
            Button("Quitter Notch") { NSApp.terminate(nil) }
        }
        // Plein écran : rangée au-dessus du bord, elle redescend avec la barre de menus.
        // …sauf pour montrer une notification.
        .offset(y: vm.isRetracted && !vm.showsAlert ? -(size.height + 24) : 0)
        .animation(.easeInOut(duration: 0.25), value: vm.isRetracted)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(spring, value: vm.isOpen)
        .animation(spring, value: settings.tab)
        .animation(spring, value: vm.showsAlert)
        .onChange(of: alerts.current?.id, initial: true) {
            vm.showsAlert = alerts.current != nil
            vm.alertHasButtons = alerts.current?.isPersistent ?? false
        }
        .animation(spring, value: showsActivity)
        .animation(spring, value: claudeCode.needsAttention)
    }

    /// Une « live activity » occupe les côtés de l'encoche repliée : Claude Code en priorité, sinon la musique.
    private var showsActivity: Bool { claudeCode.needsAttention || music.showsActivity }

    /// Teinte du verre d'après le réglage « Liquid Glass » de macOS : couleur de fond de
    /// l'apparence courante (clair ou sombre), plus ou moins opaque.
    private var glassTint: Color {
        Color(nsColor: .windowBackgroundColor).opacity(settings.systemGlassTint * 0.85)
    }

    /// Ouverte ou notification, avec le Liquid Glass activé.
    private var glassActive: Bool { (vm.isOpen || vm.showsAlert) && settings.useGlass }

    /// Repliée : noir pur, pour se fondre dans l'encoche physique.
    /// Ouverte ou notification : Liquid Glass natif, sans teinte imposée — il suit l'apparence
    /// du Mac et ses réglages d'accessibilité (réduire la transparence, augmenter le contraste).
    @ViewBuilder
    private func background(_ shape: NotchShape) -> some View {
        ZStack(alignment: .top) {
            shape.fill(.black)
                .opacity(glassActive ? 0 : 1)

            Color.clear
                .glassEffect(.regular.tint(glassTint), in: shape)
                .opacity(glassActive ? 1 : 0)
        }
    }
}
