import AppKit
import SwiftUI

/// Le gardien : une pince de fête foraine qui sort de l'encoche. Elle glisse sous la barre
/// de menus jusqu'au-dessus de l'onglet interdit, descend, compte jusqu'à trois, l'attrape
/// et le remonte dans l'encoche, qui l'avale. Un clic sur elle : elle lâche tout et remonte.
///
/// Deux petites fenêtres transparentes : le câble (qui laisse passer les clics) et la pince.
@MainActor
final class GuardianOverlay {
    /// Ce que montre la pince (lu par la vue).
    @Observable
    @MainActor
    final class Model {
        enum Eyes { case normal, focused, happy, worried }
        /// 0 : pince fermée, 1 : grande ouverte.
        var openness: CGFloat = 0.25
        var eyes: Eyes = .normal
        var message: String?
        /// L'onglet (ou l'app) attrapé, tenu entre les griffes.
        var carried: CarriedTab?
        /// Petit balancement pendant le compte à rebours.
        var wiggle = false
        /// Position du bas de l'encoche par rapport au haut du moyeu (`y` vers le haut), tant
        /// qu'elle est assez proche pour que le verre de la pince s'y soude (mitose).
        var root: CGPoint?
        /// Posée devant l'encoche (onglet juste en dessous) : un liseré la détache du noir.
        var overNotch = false
        var onTap: () -> Void = {}
    }

    /// Copie de l'onglet attrapé : son titre et sa taille à l'écran.
    struct CarriedTab: Equatable {
        var title: String
        var size: CGSize
    }

    /// Taille de la fenêtre de la pince ; le haut du moyeu (accroche du câble) est à
    /// `topMargin` du haut, centré sur `clawCenterX`. Au-dessus : la place du col de verre qui
    /// relie la pince à l'encoche pendant la mitose.
    static let topMargin: CGFloat = 90
    private static let size = NSSize(width: 340, height: 110 + topMargin)
    /// Centré : l'onglet tenu peut être plus large que la pince.
    static let clawCenterX: CGFloat = 130
    /// Distance entre le haut du moyeu et l'endroit où les griffes se referment.
    static let grabDepth: CGFloat = 50
    /// Profondeur sous l'encoche où la pince glisse : assez bas pour s'en être détachée.
    private static let cruiseDepth: CGFloat = 60
    /// Profondeur où la pince s'est détachée de l'encoche : ses griffes sortent alors.
    private static let splitDepth: CGFloat = 42

    private let model = Model()
    private var clawPanel: NSPanel?
    private var cablePanel: NSPanel?
    private var script: Task<Void, Never>?
    private var busy = false
    private var grabbed = false
    /// Accroche du câble, en coordonnées de l'écran (origine en bas).
    private var hook: NSPoint = .zero
    /// Haut du câble (bas de l'encoche / de la barre de menus) et centre de l'encoche.
    private var railY: CGFloat = 0
    private var notchX: CGFloat = 0
    /// Vrai pendant la sortie de l'encoche et le retour : elle peut s'y souder (mitose).
    private var merging = false
    /// Demi-largeur de la zone noire de l'encoche (avec ses activités de part et d'autre).
    private var notchHalfWidth: CGFloat = 150

    private var stillThere: () async -> Bool = { false }
    private var close: () -> Void = {}
    private var chased: () -> Void = {}

    var isIdle: Bool { !busy }

    init() {
        model.onTap = { [weak self] in self?.chase() }
    }

    /// Lance l'intervention. `grabPoint` : où attraper (l'onglet, ou le haut de la fenêtre),
    /// en coordonnées de l'écran.
    func intercept(
        tab: CarriedTab,
        grabPoint: NSPoint,
        stillThere: @escaping () async -> Bool,
        close: @escaping () -> Void,
        chased: @escaping () -> Void
    ) {
        guard !busy else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(grabPoint) } ?? NSScreen.main
        guard let screen else { return }
        busy = true
        grabbed = false
        self.stillThere = stillThere
        self.close = close
        self.chased = chased

        // Le câble part du bas de l'encoche (ou de la barre de menus).
        let top = screen.frame.maxY
        let menuBar = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : top - screen.visibleFrame.maxY
        railY = top - max(menuBar, 24)
        notchX = screen.frame.midX
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            // Encoche du Mac, élargie par les activités affichées de chaque côté.
            notchHalfWidth = (screen.frame.width - left.width - right.width) / 2 + 80
        }
        // Cachée derrière l'encoche au départ.
        hook = NSPoint(x: notchX, y: top + 10)

        model.openness = 0.25
        model.eyes = .normal
        model.message = nil
        model.carried = nil
        model.wiggle = false
        model.overNotch = false
        clawPanel?.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        showPanels()

        // Griffes refermées pile sur l'onglet (le moyeu peut passer sur la barre de menus).
        let target = NSPoint(
            x: min(max(grabPoint.x, screen.frame.minX + 50), screen.frame.maxX - 50),
            y: min(grabPoint.y + Self.grabDepth, top - 2)
        )
        script = Task { [weak self] in
            await self?.run(tab: tab, to: target)
        }
    }

    /// Remonte sans rien fermer (gardien désactivé en cours de route).
    func leave() {
        guard busy, !grabbed else { return }
        script?.cancel()
        script = Task { [weak self] in await self?.goHome(speed: 380) }
    }

    // MARK: - Déroulé

    private func run(tab: CarriedTab, to target: NSPoint) async {
        do {
            // Elle bourgeonne de l'encoche et s'en détache…
            merging = true
            try await move(to: NSPoint(x: notchX, y: railY - Self.cruiseDepth), speed: 45)
            merging = false
            // …glisse jusque sous l'onglet…
            try await move(to: NSPoint(x: target.x, y: railY - Self.cruiseDepth), speed: 220)
            // …se hisse au-dessus, griffes ouvertes, et se pose dessus.
            model.openness = 1
            model.eyes = .focused
            try await move(to: NSPoint(x: target.x, y: target.y + 16), speed: 160)
            try await move(to: target, speed: 60)

            model.wiggle = true
            for count in [3, 2, 1] {
                model.message = "\(count)…"
                try await Task.sleep(for: .seconds(1))
            }
            model.wiggle = false
            model.message = nil

            guard await stillThere() else {
                model.eyes = .normal
                model.openness = 0.25
                model.message = "Ah, déjà parti ?"
                try await Task.sleep(for: .seconds(1))
                model.message = nil
                await goHome(speed: 300)
                return
            }
            // Attrapé : le vrai onglet disparaît du navigateur au moment où sa copie se
            // retrouve dans la pince, qui l'emporte dans l'encoche.
            grabbed = true
            model.openness = 0
            model.carried = tab
            model.eyes = .happy
            close()
            try await Task.sleep(for: .seconds(0.5))
            // Elle l'arrache vers le haut avant de repartir.
            try? await move(to: NSPoint(x: hook.x, y: hook.y + 10), speed: 80, cancellable: false)
            await goHome(speed: 220)
        } catch {
            // Annulé : `chase` ou `leave` a pris la suite.
        }
    }

    /// Clic sur la pince : elle a peur, lâche tout et file dans l'encoche.
    private func chase() {
        guard busy, !grabbed else { return }
        script?.cancel()
        chased()
        model.wiggle = false
        model.openness = 1
        model.eyes = .worried
        model.message = "D'accord, d'accord…"
        script = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.5))
            self?.model.message = nil
            await self?.goHome(speed: 650)
        }
    }

    /// Remonte, revient sous l'encoche et y rentre. Non annulable : elle finit toujours rangée.
    private func goHome(speed: CGFloat) async {
        merging = false
        try? await move(to: NSPoint(x: hook.x, y: railY - Self.cruiseDepth), speed: speed, cancellable: false)
        try? await move(to: NSPoint(x: notchX, y: railY - Self.cruiseDepth), speed: speed, cancellable: false)
        merging = true
        try? await move(to: NSPoint(x: notchX, y: railY + 85), speed: min(speed * 0.3, 90), cancellable: false)
        clawPanel?.orderOut(nil)
        cablePanel?.orderOut(nil)
        model.carried = nil
        grabbed = false
        busy = false
    }

    // MARK: - Déplacement

    /// Déplacement en douceur : la pince accélère au départ et ralentit à l'arrivée.
    /// `speed` : vitesse moyenne, en points par seconde.
    private func move(to destination: NSPoint, speed: CGFloat, cancellable: Bool = true) async throws {
        let start = hook
        let distance = hypot(destination.x - start.x, destination.y - start.y)
        guard distance > 0.5 else { return }
        let duration = Double(distance / speed)
        let began = Date()
        while true {
            if cancellable { try Task.checkCancellation() }
            let t = min(Date().timeIntervalSince(began) / duration, 1)
            // Accélération puis freinage (courbe « smoothstep »).
            let eased = CGFloat(t * t * (3 - 2 * t))
            hook = NSPoint(
                x: start.x + (destination.x - start.x) * eased,
                y: start.y + (destination.y - start.y) * eased)
            layout()
            if t >= 1 { return }
            if cancellable {
                try await Task.sleep(for: .milliseconds(16))
            } else {
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    /// Place la pince sous l'accroche, et le câble entre le rail et l'accroche.
    private func layout() {
        clawPanel?.setFrameOrigin(
            NSPoint(x: hook.x - Self.clawCenterX, y: hook.y + Self.topMargin - Self.size.height))
        // Près de l'encoche, le verre de la pince s'y soude : elle en bourgeonne, puis s'en détache.
        let rise = railY - hook.y
        let root = merging && rise < Self.splitDepth ? CGPoint(x: notchX - hook.x, y: rise) : nil
        if root != model.root { model.root = root }
        // Onglet sous l'encoche : la pince passe devant elle au lieu de s'y cacher.
        let overNotch = !merging && abs(hook.x - notchX) < notchHalfWidth + 30 && hook.y > railY - 30
        if overNotch != model.overNotch {
            model.overNotch = overNotch
            clawPanel?.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + (overNotch ? 4 : 2))
        }
        let length = max(railY - hook.y + 4, 0)
        cablePanel?.setFrame(NSRect(x: hook.x - 1.5, y: hook.y - 2, width: 3, height: length + 2), display: true)
        cablePanel?.alphaValue = length > 0 ? 1 : 0
    }

    private func showPanels() {
        let claw = clawPanel ?? makePanel(size: Self.size, clickable: true)
        if clawPanel == nil {
            claw.contentView = FirstClickHostingView(rootView: ClawView(model: model, centerX: Self.clawCenterX))
            clawPanel = claw
        }
        let cable = cablePanel ?? makePanel(size: NSSize(width: 3, height: 10), clickable: false)
        if cablePanel == nil {
            let view = NSView()
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
            view.layer?.borderColor = NSColor(white: 1, alpha: 0.18).cgColor
            view.layer?.borderWidth = 0.5
            cable.contentView = view
            cablePanel = cable
        }
        layout()
        cable.orderFrontRegardless()
        claw.orderFrontRegardless()
    }

    private func makePanel(size: NSSize, clickable: Bool) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // Juste sous l'encoche (`mainMenu + 3`) : la pince en sort et y rentre.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = !clickable
        // Aussi par-dessus une vidéo en plein écran.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }
}

// MARK: - Dessin

/// La pince : un moyeu noir en forme d'encoche, avec deux yeux, et deux griffes. Près de
/// l'encoche, elle en bourgeonne comme une cellule qui se divise (même effet « gluant » que
/// la bulle des activités) ; ses griffes sortent une fois détachée.
private struct ClawView: View {
    let model: GuardianOverlay.Model
    let centerX: CGFloat

    private static let hubSize = CGSize(width: 46, height: 24)
    private static let armLength: CGFloat = 40
    private var top: CGFloat { GuardianOverlay.topMargin }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let root = model.root {
                mitosis(root: root)
            }
            swinging(
                claw
                    .scaleEffect(model.root == nil ? 1 : 0.2, anchor: .top)
                    .opacity(model.root == nil ? 1 : 0)
                    .animation(.spring(response: 0.45, dampingFraction: 0.55), value: model.root == nil))
            swinging(
                ZStack(alignment: .top) {
                    if model.root == nil { hubShape }
                    eyes.padding(.top, Self.hubSize.height / 2 - 4)
                }
                .scaleEffect(budScale, anchor: .top))

            if let message = model.message {
                Text(message)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.black).overlay(Capsule().strokeBorder(.white.opacity(0.18))))
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                    .offset(x: centerX + Self.hubSize.width / 2 + 26, y: top + 2)
                    .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
                    .id(message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: model.message)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: model.openness)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.carried)
    }

    /// Le moyeu grossit en sortant de l'encoche.
    private var budScale: CGFloat {
        guard let root = model.root else { return 1 }
        return 0.45 + 0.55 * min(max(root.y / 40, 0), 1)
    }

    /// Le bas de l'encoche et le moyeu, flous puis seuillés : tant qu'ils sont proches, un col
    /// noir les relie, qui s'étire puis cède.
    private func mitosis(root: CGPoint) -> some View {
        let scale = budScale
        let hub = Self.hubSize
        return Canvas { context, _ in
            context.addFilter(.alphaThreshold(min: 0.5, color: .black))
            context.addFilter(.blur(radius: 7))
            context.drawLayer { layer in
                // Bas de l'encoche, caché par elle : le col y prend racine.
                let notch = CGRect(x: centerX + root.x - 34, y: top - root.y - 30, width: 68, height: 30)
                layer.fill(Path(roundedRect: notch, cornerRadius: 10), with: .color(.black))
                let width = hub.width * scale
                let rect = CGRect(x: centerX - width / 2, y: top, width: width, height: hub.height * scale)
                layer.fill(Path(roundedRect: rect, cornerRadius: 11 * scale), with: .color(.black))
            }
        }
        .allowsHitTesting(false)
    }

    /// Place une partie de la pince sous l'accroche, avec son balancement ; un clic la chasse.
    private func swinging(_ content: some View) -> some View {
        content
            .frame(width: centerX * 2, height: Self.hubSize.height + Self.armLength + 10, alignment: .top)
            .rotationEffect(.degrees(model.wiggle ? 4 : -4), anchor: .top)
            .animation(
                model.wiggle ? .easeInOut(duration: 0.18).repeatForever(autoreverses: true) : .default,
                value: model.wiggle
            )
            .contentShape(Rectangle())
            .onTapGesture { model.onTap() }
            .help("Clique pour la chasser")
            .padding(.top, top)
    }

    private var claw: some View {
        let angle = 6 + 30 * model.openness
        return ZStack(alignment: .top) {
            // Ce qui a été attrapé, tenu entre les bouts des griffes.
            if let carried = model.carried {
                TabCopy(tab: carried)
                    .offset(y: GuardianOverlay.grabDepth - carried.size.height / 2)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            Arm(mirrored: false)
                .rotationEffect(.degrees(angle), anchor: .top)
                .offset(x: -12, y: Self.hubSize.height - 6)
            Arm(mirrored: true)
                .rotationEffect(.degrees(-angle), anchor: .top)
                .offset(x: 12, y: Self.hubSize.height - 6)
        }
    }

    /// Le moyeu, en forme d'encoche : bord du haut droit, coins du bas arrondis.
    private var hubShape: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 3, bottomLeadingRadius: 11, bottomTrailingRadius: 11, topTrailingRadius: 3)
        return
            shape
            .fill(model.overNotch ? Color(white: 0.13) : .black)
            .overlay(shape.strokeBorder(.white.opacity(model.overNotch ? 0.55 : 0.2), lineWidth: model.overNotch ? 1 : 0.75))
            .frame(width: Self.hubSize.width, height: Self.hubSize.height)
            .shadow(color: model.overNotch ? .white.opacity(0.25) : .black.opacity(0.35), radius: 3, y: model.overNotch ? 0 : 2)
            .animation(.easeInOut(duration: 0.25), value: model.overNotch)
    }

    private var eyes: some View {
        HStack(spacing: 12) {
            eye(tilt: -1)
            eye(tilt: 1)
        }
    }

    @ViewBuilder
    private func eye(tilt: Double) -> some View {
        switch model.eyes {
        case .normal:
            RoundedRectangle(cornerRadius: 1.5).fill(.white).frame(width: 5, height: 8)
        case .focused:
            // Il plisse les yeux en visant.
            RoundedRectangle(cornerRadius: 1).fill(.white).frame(width: 7, height: 3)
                .rotationEffect(.degrees(12 * tilt))
        case .happy:
            HappyEye().stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round)).frame(width: 7, height: 4)
        case .worried:
            RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: 6, height: 9)
                .rotationEffect(.degrees(-10 * tilt))
        }
    }
}

/// Un œil content : « ^ ».
private struct HappyEye: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

/// Une griffe : une tige qui descend, puis un crochet tourné vers l'intérieur.
private struct Arm: View {
    let mirrored: Bool

    var body: some View {
        Canvas { context, size in
            let w = size.width
            var path = Path()
            // Tige.
            path.move(to: CGPoint(x: w / 2 - 2.5, y: 0))
            path.addLine(to: CGPoint(x: w / 2 + 2.5, y: 0))
            path.addLine(to: CGPoint(x: w / 2 + 2.5, y: 26))
            // Crochet vers l'intérieur (la droite pour la griffe de gauche).
            path.addLine(to: CGPoint(x: w - 1, y: 36))
            path.addLine(to: CGPoint(x: w - 4, y: 40))
            path.addLine(to: CGPoint(x: w / 2 - 2.5, y: 31))
            path.closeSubpath()
            if mirrored {
                path = path.applying(CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -w, y: 0))
            }
            context.fill(
                path,
                with: .linearGradient(
                    Gradient(colors: [Color(white: 0.42), Color(white: 0.16)]),
                    startPoint: .zero, endPoint: CGPoint(x: w, y: size.height)))
            context.stroke(path, with: .color(.white.opacity(0.18)), lineWidth: 0.5)
        }
        .frame(width: 16, height: 42)
    }
}

/// Copie de l'onglet attrapé, à sa taille : icône et titre, comme dans la barre d'onglets.
private struct TabCopy: View {
    let tab: GuardianOverlay.CarriedTab

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(tab.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .frame(width: tab.size.width, height: tab.size.height)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
        )
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.primary.opacity(0.12)))
        .rotationEffect(.degrees(-3))
    }
}
