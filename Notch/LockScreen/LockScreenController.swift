import AppKit
import Observation
import SwiftUI

/// Encoche sur l'écran de verrouillage : un cadenas dans l'encoche, les activités sous l'horloge,
/// le lecteur de musique en bas au-dessus de la photo de profil,
/// et un son au verrouillage / déverrouillage si c'est réglé.
@Observable
@MainActor
final class LockScreenController {
    enum Phase { case hidden, locked, unlocking }

    private(set) var phase: Phase = .hidden
    private(set) var notchSize = CGSize(width: 190, height: 32)

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private var windows: [NSWindow] = []
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    /// Lecteur de musique, en bas au-dessus de la photo de profil.
    static let musicCardSize = CGSize(width: 420, height: 124)
    /// Zone des cartes d'activité, sous l'horloge.
    static let activitiesSize = CGSize(width: 420, height: 380)
    /// Part du haut de l'écran prise par la date et l'horloge de l'écran verrouillé.
    static let clockFraction: CGFloat = 0.31
    /// Part du bas de l'écran prise par la photo de profil, le nom et le mot de passe.
    static let loginFraction: CGFloat = 0.21

    init(services: AppServices) {
        self.services = services
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didLock() }
        }
        center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didUnlock() }
        }
        // Écran branché ou débranché pendant le verrouillage : on replace tout.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensDidChange() }
        }
    }

    private var settings: AppSettings { services.settings }

    // MARK: - Verrouillage

    private func didLock() {
        settings.lockSound.play()
        guard settings.showOnLockScreen else { return }
        hideTask?.cancel()
        showWindows()
    }

    @ObservationIgnored private var relayoutTask: Task<Void, Never>?

    /// Les changements d'écran arrivent en rafale : on attend la fin avant de tout replacer.
    private func screensDidChange() {
        guard phase == .locked else { return }
        relayoutTask?.cancel()
        relayoutTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, self.phase == .locked else { return }
            self.showWindows()
        }
    }

    /// Écran de l'encoche : celui du Mac quand il est ouvert (sa vraie encoche), sinon l'écran principal.
    static func lockScreen() -> NSScreen? {
        NSScreen.screens.first(where: \.hasNotch) ?? NSScreen.screens.first
    }

    private func showWindows() {
        closeWindows()
        guard let space = LockScreenSpace.shared, let screen = Self.lockScreen() else { return }
        notchSize = screen.notchSize
        phase = .locked

        let notchWindow = makeWindow(
            frame: NSRect(
                x: screen.frame.midX - LockNotchView.width(for: notchSize) / 2,
                y: screen.frame.maxY - notchSize.height,
                width: LockNotchView.width(for: notchSize),
                height: notchSize.height
            ),
            content: LockNotchView(),
            clickable: false
        )
        windows.append(notchWindow)

        // Activités empilées sous l'horloge (comme sur iPhone), mises à jour en direct.
        let size = Self.activitiesSize
        let top = screen.frame.maxY - screen.frame.height * Self.clockFraction
        let activitiesWindow = makeWindow(
            frame: NSRect(
                x: screen.frame.midX - size.width / 2, y: top - size.height,
                width: size.width, height: size.height),
            content: LockActivitiesView(),
            clickable: true
        )
        windows.append(activitiesWindow)

        // Lecteur en bas, juste au-dessus de la photo de profil.
        let music = Self.musicCardSize
        let musicWindow = makeWindow(
            frame: NSRect(
                x: screen.frame.midX - music.width / 2,
                y: screen.frame.minY + screen.frame.height * Self.loginFraction,
                width: music.width, height: music.height),
            content: LockMusicArea(),
            clickable: true
        )
        windows.append(musicWindow)
        windows.forEach(space.add)
    }

    private func didUnlock() {
        settings.unlockSound.play()
        guard phase == .locked else { return }
        // Le cadenas s'ouvre, puis tout s'efface.
        phase = .unlocking
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.phase = .hidden
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.closeWindows()
        }
    }

    // MARK: - Fenêtres

    private func makeWindow(frame: NSRect, content: some View, clickable: Bool) -> NSWindow {
        let window = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .screenSaver
        window.ignoresMouseEvents = !clickable
        window.isReleasedWhenClosed = false
        window.canBecomeVisibleWithoutLogin = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let root =
            content
            .environment(self)
            .environment(services)
            .environment(\.colorScheme, .dark)
        window.contentView = NSHostingView(rootView: root)
        window.orderFrontRegardless()
        return window
    }

    private func closeWindows() {
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
    }

}

/// Sons proposés au verrouillage et au déverrouillage (sons système de macOS).
enum LockSound: String, CaseIterable, Identifiable {
    case none
    case pop = "Pop"
    case glass = "Glass"
    case tink = "Tink"
    case purr = "Purr"
    case bottle = "Bottle"
    case morse = "Morse"

    var id: String { rawValue }
    var label: String { self == .none ? "Aucun" : rawValue }

    func play() {
        guard self != .none else { return }
        NSSound(named: NSSound.Name(rawValue))?.play()
    }
}

// MARK: - Vues

/// Encoche sur l'écran verrouillé : un cadenas à gauche, qui s'ouvre au déverrouillage.
struct LockNotchView: View {
    @Environment(LockScreenController.self) private var lock
    @State private var appeared = false

    static let slotWidth: CGFloat = 40
    static func width(for notch: CGSize) -> CGFloat { notch.width + 2 * slotWidth + 2 * 6 }

    var body: some View {
        let unlocking = lock.phase == .unlocking
        let visible = lock.phase != .hidden
        let shape = NotchShape(topRadius: 6, bottomRadius: 10)
        ZStack {
            shape.fill(.black)
            HStack(spacing: 0) {
                Image(systemName: unlocking ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(unlocking ? .green : .white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: Self.slotWidth)
                    .opacity(appeared ? 1 : 0)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
        }
        .frame(width: appeared ? Self.width(for: lock.notchSize) : lock.notchSize.width)
        .frame(maxWidth: .infinity)
        .opacity(visible ? 1 : 0)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: appeared)
        .animation(.snappy, value: lock.phase)
        .onAppear { appeared = true }
    }
}

/// Lecteur de musique en bas de l'écran verrouillé.
struct LockMusicCard: View {
    var body: some View {
        ExpandedMusicView()
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassEffect(.regular.tint(.black.opacity(0.35)), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}
