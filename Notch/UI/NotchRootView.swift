import SwiftUI

struct NotchRootView: View {
    @Environment(NotchViewModel.self) private var vm
    @Environment(AppSettings.self) private var settings
    @Environment(MusicController.self) private var music
    @Environment(ClaudeCodeMonitor.self) private var claudeCode
    @Environment(LaunchAtLogin.self) private var launchAtLogin

    private let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
    private let tabTransition = AnyTransition.opacity.combined(with: .scale(scale: 0.97))

    var body: some View {
        let size = vm.shapeSize(showsActivity: showsActivity)
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
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        .shadow(color: .black.opacity(vm.isOpen ? 0.35 : 0), radius: 18, y: 8)
        .contextMenu {
            Toggle("Liquid Glass", isOn: Binding(get: { settings.useGlass }, set: { settings.useGlass = $0 }))
            if launchAtLogin.isInstalledCopy {
                Toggle("Ouvrir au démarrage", isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.set($0) }))
            }
            Divider()
            Button("Quitter Notch") { NSApp.terminate(nil) }
        }
        // Plein écran : rangée au-dessus du bord, elle redescend avec la barre de menus.
        .offset(y: vm.isRetracted ? -(size.height + 24) : 0)
        .animation(.easeInOut(duration: 0.25), value: vm.isRetracted)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(spring, value: vm.isOpen)
        .animation(spring, value: showsActivity)
        .animation(spring, value: claudeCode.needsAttention)
        .preferredColorScheme(.dark)
    }

    /// Une « live activity » occupe les côtés de l'encoche repliée : Claude Code en priorité, sinon la musique.
    private var showsActivity: Bool { claudeCode.needsAttention || music.showsActivity }

    /// Repliée : noir pur, pour se fondre dans l'encoche physique.
    /// Ouverte : Liquid Glass teinté. L'encoche matérielle masque déjà ce qui est
    /// derrière elle, inutile de dessiner quoi que ce soit dessous.
    @ViewBuilder
    private func background(_ shape: NotchShape) -> some View {
        let glass = vm.isOpen && settings.useGlass
        ZStack(alignment: .top) {
            shape.fill(.black)
                .opacity(glass ? 0 : 1)

            Color.clear
                .glassEffect(.regular.tint(.black.opacity(0.5)), in: shape)
                .opacity(glass ? 1 : 0)
        }
    }
}
