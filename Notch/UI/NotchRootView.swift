import SwiftUI

struct NotchRootView: View {
    @Environment(NotchViewModel.self) private var vm
    @Environment(AppSettings.self) private var settings
    @Environment(MusicController.self) private var music

    private let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)

    var body: some View {
        let size = vm.shapeSize(showsActivity: music.showsActivity)
        let shape = NotchShape(topRadius: vm.topRadius, bottomRadius: vm.bottomRadius)

        ZStack(alignment: .top) {
            background(shape)

            if vm.isOpen {
                VStack(spacing: 0) {
                    Color.clear.frame(height: vm.notchSize.height)
                    HStack(spacing: 20) {
                        ExpandedMusicView()
                            .frame(width: 330)
                        Rectangle()
                            .fill(.white.opacity(0.12))
                            .frame(width: 1)
                            .padding(.vertical, 4)
                        CalendarView()
                    }
                        .padding(.top, 8)
                        .padding(.bottom, 18)
                        .padding(.horizontal, 24 + vm.topRadius)
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top))
                        .animation(spring.delay(0.06)),
                    removal: .opacity.animation(.easeOut(duration: 0.12))
                ))
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
            Divider()
            Button("Quitter Notch") { NSApp.terminate(nil) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(spring, value: vm.isOpen)
        .animation(spring, value: music.showsActivity)
        .preferredColorScheme(.dark)
    }

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
