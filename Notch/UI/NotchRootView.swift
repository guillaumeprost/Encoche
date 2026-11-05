import SwiftUI

struct NotchRootView: View {
    @Environment(NotchViewModel.self) private var vm
    @Environment(AppSettings.self) private var settings
    @Environment(MusicController.self) private var music
    @Environment(HUDCenter.self) private var hud
    @Environment(PrivacyMonitor.self) private var privacy
    @Environment(DownloadMonitor.self) private var downloads
    @Environment(ClaudeCodeMonitor.self) private var claudeCode
    @Environment(AlertCenter.self) private var alerts
    /// Apparence du Mac (clair / sombre).
    @Environment(\.colorScheme) private var systemColorScheme

    private let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    private let tabTransition = AnyTransition.opacity.combined(with: .scale(scale: 0.97))

    var body: some View {
        let size = vm.shapeSize(
            showsActivity: showsActivity,
            extraHeight: NotchViewModel.extraHeight(for: settings.tab)
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
                        case .calendar: CalendarTab().transition(tabTransition)
                        case .music: MusicTab().transition(tabTransition)
                        case .house: HomeControlView().transition(tabTransition)
                        case .shelf: ShelfView().transition(tabTransition)
                        case .clipboard: ClipboardView().transition(tabTransition)
                        case .notifications: NotificationHistoryView().transition(tabTransition)
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
            } else {
                // L'activité en cours reste affichée quand un indicateur (volume…) s'ajoute dessous.
                VStack(spacing: 0) {
                    ZStack {
                        if let primary = activities.first {
                            activityView(primary)
                                .padding(.horizontal, vm.topRadius)
                                .id(primary)
                                .transition(.opacity)
                        }
                    }
                    .frame(height: vm.showsHUD ? vm.notchSize.height : vm.activityHeight)
                    if vm.showsHUD, let kind = hud.current {
                        HUDView(kind: kind)
                            .padding(.horizontal, 14 + vm.topRadius)
                            .frame(height: NotchViewModel.hudHeight)
                            .padding(.bottom, 2)
                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                    }
                }
            }
        }
        // En verre, le contenu suit l'apparence du Mac ; sur fond noir (repliée, ou verre
        // désactivé), il reste en style sombre pour rester lisible.
        .environment(\.colorScheme, glassActive ? systemColorScheme : .dark)
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        // Une deuxième activité en même temps : petite bulle à droite, comme sur iPhone.
        .overlay(alignment: .topTrailing) {
            if showsBubble, let second = activities.dropFirst().first {
                ActivityBubble(activity: second)
                    .frame(width: vm.activityHeight, height: vm.activityHeight)
                    .offset(x: vm.activityHeight + 6)
                    .id(second)
                    .transition(.scale(scale: 0.4, anchor: .leading).combined(with: .opacity))
            }
        }
        .animation(spring, value: activities)
        .contextMenu {
            Button("Réglages…") { settings.openSettings() }
            Divider()
            Button("Quitter Encoche") { NSApp.terminate(nil) }
        }
        // Plein écran : rangée au-dessus du bord, elle redescend avec la barre de menus.
        // …sauf pour montrer une notification.
        .offset(y: vm.isRetracted && !vm.showsAlert ? -(size.height + 24) : 0)
        .animation(.easeInOut(duration: 0.25), value: vm.isRetracted)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(spring, value: vm.isOpen)
        .animation(spring, value: settings.tab)
        .animation(spring, value: vm.showsAlert)
        .animation(spring, value: vm.showsHUD)
        .onChange(of: hud.current, initial: true) { vm.showsHUD = hud.current != nil }
        .onChange(of: alerts.current?.id, initial: true) { updateAlert() }
        .onChange(of: vm.isPrimaryScreen) { updateAlert() }
        .onChange(of: settings.notificationsOnPrimaryScreenOnly) { updateAlert() }
        .animation(spring, value: showsActivity)
        .animation(spring, value: claudeCode.needsAttention)
    }

    /// Affiche la notification en cours, sur l'écran principal seulement si c'est réglé ainsi.
    private func updateAlert() {
        let allowed = vm.isPrimaryScreen || !settings.notificationsOnPrimaryScreenOnly
        vm.showsAlert = allowed && alerts.current != nil
        vm.alertHasButtons = alerts.current?.isPersistent ?? false
    }

    /// Une « live activity » occupe les côtés de l'encoche repliée, par priorité : Claude Code qui
    /// t'attend, caméra ou micro, téléchargement, Claude Code au travail, puis la musique.
    private var showsActivity: Bool { !activities.isEmpty }

    private var activities: [LiveActivity] {
        LiveActivity.active(settings: settings, claudeCode: claudeCode, privacy: privacy, downloads: downloads, music: music)
    }

    /// La bulle n'accompagne que l'encoche repliée, sans notification (elle reste avec le volume).
    private var showsBubble: Bool { !vm.isOpen && !vm.showsAlert && !vm.isRetracted }

    @ViewBuilder
    private func activityView(_ activity: LiveActivity) -> some View {
        switch activity {
        case .claudeWaiting: CollapsedClaudeView(slotWidth: vm.activitySlotWidth)
        case .privacy: CollapsedPrivacyView(slotWidth: vm.activitySlotWidth)
        case .download: CollapsedDownloadView(slotWidth: vm.activitySlotWidth)
        case .claudeWorking: CollapsedClaudeWorkingView(slotWidth: vm.activitySlotWidth)
        case .music: CollapsedMusicView(slotWidth: vm.activitySlotWidth)
        }
    }

    /// Teinte du verre d'après le réglage « Liquid Glass » de macOS : couleur de fond de
    /// l'apparence courante (clair ou sombre), plus ou moins opaque.
    private var glassTint: Color {
        Color(nsColor: .windowBackgroundColor).opacity(settings.systemGlassTint * 0.85)
    }

    /// Ouverte ou notification, avec le Liquid Glass activé.
    /// Notifications et indicateurs restent toujours noirs, comme l'encoche matérielle (effet
    /// Dynamic Island) ; seule l'encoche ouverte peut passer en verre, si l'option est activée.
    private var glassActive: Bool { vm.isOpen && settings.notchStyle == .glass }

    /// Ouverte en verre noir.
    private var darkGlassActive: Bool { vm.isOpen && settings.notchStyle == .darkGlass }

    private var darkGlassGradient: LinearGradient {
        let height = vm.shapeSize(
            showsActivity: false,
            extraHeight: NotchViewModel.extraHeight(for: settings.tab)
        ).height
        let solid = min(max((vm.notchSize.height + 6) / max(height, 1), 0), 1)
        return LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: solid),
                .init(color: .black.opacity(0.35), location: min(solid + 0.14, 1)),
                .init(color: .black.opacity(0.04), location: min(solid + 0.4, 1)),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Liseré du verre : invisible contre l'encoche du Mac, il s'éclaire vers le bas.
    private var darkGlassRim: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(0), location: 0.25),
                .init(color: .white.opacity(0.14), location: 0.7),
                .init(color: .white.opacity(0.32), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Noir pur par défaut, pour se fondre dans l'encoche physique, y compris ouverte et pour
    /// les notifications. En option, l'encoche ouverte passe en Liquid Glass natif, qui suit
    /// l'apparence du Mac et son réglage de transparence.
    @ViewBuilder
    private func background(_ shape: NotchShape) -> some View {
        ZStack(alignment: .top) {
            shape.fill(.black)
                .opacity(glassActive || darkGlassActive ? 0 : 1)

            Color.clear
                .glassEffect(.regular.tint(glassTint), in: shape)
                .opacity(glassActive ? 1 : 0)

            // Verre noir : verre sombre sous un dégradé, noir pur sur la hauteur de l'encoche
            // du Mac (elle s'y fond), puis de plus en plus transparent vers le bas.
            // Le voile noir s'efface vite sous l'encoche pour laisser vivre le verre (flou, reflets),
            // et un fin liseré lumineux, plus marqué vers le bas, dessine le bord comme sur macOS 26.
            ZStack {
                Color.clear
                    .glassEffect(.regular.tint(.black.opacity(0.22)), in: shape)
                shape.fill(darkGlassGradient)
                // Léger reflet clair dans le bas du verre.
                shape.fill(LinearGradient(
                    stops: [.init(color: .white.opacity(0), location: 0.55), .init(color: .white.opacity(0.07), location: 1)],
                    startPoint: .top, endPoint: .bottom
                ))
                shape.stroke(darkGlassRim, lineWidth: 1.5)
            }
            .opacity(darkGlassActive ? 1 : 0)
        }
    }
}
