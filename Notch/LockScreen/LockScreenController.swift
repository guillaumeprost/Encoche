import AppKit
import Observation
import SwiftUI

/// Encoche sur l'écran de verrouillage : un cadenas dans l'encoche, le lecteur de musique en bas,
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

    static let musicCardSize = CGSize(width: 420, height: 124)

    init(services: AppServices) {
        self.services = services
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didLock() }
        }
        center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didUnlock() }
        }
    }

    private var settings: AppSettings { services.settings }

    // MARK: - Verrouillage

    private func didLock() {
        settings.lockSound.play()
        guard settings.showOnLockScreen, let space = LockScreenSpace.shared, let screen = NSScreen.screens.first else { return }
        hideTask?.cancel()
        closeWindows()
        notchSize = Self.notchSize(of: screen)
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

        if settings.lockScreenMusic, services.music.track != nil {
            let size = Self.musicCardSize
            let musicWindow = makeWindow(
                frame: NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.minY + 120,
                              width: size.width, height: size.height),
                content: LockMusicCard(),
                clickable: true
            )
            windows.append(musicWindow)
        }
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
        let root = content
            .environment(self)
            .environment(services)
            .environment(\.colorScheme, .dark)
        window.contentView = NSHostingView(rootView: root)
        window.orderFrontRegardless()
        return window
    }

    private func closeWindows() {
        windows.forEach { $0.orderOut(nil); $0.close() }
        windows.removeAll()
    }

    private static func notchSize(of screen: NSScreen) -> CGSize {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return CGSize(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
        }
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        return CGSize(width: 190, height: menuBarHeight > 0 ? menuBarHeight : 24)
    }
}

/// Sons proposés au verrouillage et au déverrouillage (sons système de macOS).
enum LockSound: String, CaseIterable, Identifiable {
    case none, pop = "Pop", glass = "Glass", tink = "Tink", purr = "Purr", bottle = "Bottle", morse = "Morse"

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
    @Environment(LockScreenController.self) private var lock

    var body: some View {
        ExpandedMusicView()
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassEffect(.regular.tint(.black.opacity(0.35)), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .opacity(lock.phase == .locked ? 1 : 0)
            .animation(.easeOut(duration: 0.3), value: lock.phase)
    }
}
