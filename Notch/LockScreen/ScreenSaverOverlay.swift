import AppKit
import SwiftUI

/// Ce que fait Claude Code, par-dessus l'économiseur d'écran : la même carte que sur l'écran
/// verrouillé, en bas de l'écran principal, tant qu'une session travaille ou t'attend.
@MainActor
final class ScreenSaverOverlay {
    private let services: AppServices
    private var window: NSWindow?

    private static let size = CGSize(width: 460, height: 96)

    init(services: AppServices) {
        self.services = services
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("com.apple.screensaver.didstart"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.show() }
        }
        center.addObserver(forName: .init("com.apple.screensaver.didstop"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func show() {
        guard services.settings.showOnLockScreen, window == nil, let screen = NSScreen.screens.first else { return }
        let frame = NSRect(
            x: screen.frame.midX - Self.size.width / 2, y: screen.frame.minY + 90,
            width: Self.size.width, height: Self.size.height)
        let window = NSPanel(
            contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        // Juste au-dessus des fenêtres de l'économiseur d'écran.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.canBecomeVisibleWithoutLogin = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.contentView = NSHostingView(
            rootView: ScreenSaverClaudeView()
                .environment(services)
                .environment(\.colorScheme, .dark))
        window.orderFrontRegardless()
        self.window = window
    }

    private func hide() {
        window?.orderOut(nil)
        window?.close()
        window = nil
    }
}

/// Carte Claude Code de l'économiseur : la session qui t'attend, sinon celle qui travaille.
private struct ScreenSaverClaudeView: View {
    @Environment(ClaudeCodeMonitor.self) private var claudeCode

    private var session: ClaudeCodeSession? {
        claudeCode.sortedSessions.first { $0.state == .waiting } ?? claudeCode.workingSession
    }

    var body: some View {
        ZStack {
            if let session {
                LockClaudeCard(session: session)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.smooth(duration: 0.4), value: session?.id)
        .animation(.smooth(duration: 0.3), value: session?.detail)
    }
}
