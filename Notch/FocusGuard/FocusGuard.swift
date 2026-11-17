import AppKit
import Carbon
import Observation
import SwiftUI

/// Gardien anti-distraction : une fois activé, si tu passes sur un site ou une app de ta
/// liste, le petit personnage traverse l'écran pour fermer l'onglet ou l'app. Un clic sur
/// lui le chasse : il repart, et te laisse tranquille sur ce site quelques minutes.
@Observable
@MainActor
final class FocusGuard {
    /// Ce que le gardien vient fermer.
    enum Target: Equatable {
        /// Onglet d'un navigateur sur un site interdit (domaine de la liste).
        case site(domain: String, browserID: String, pid: pid_t)
        /// App interdite.
        case app(bundleID: String, name: String, pid: pid_t)

        /// Clé de la liste et du répit après un coup de balai.
        var key: String {
            switch self {
            case .site(let domain, _, _): domain
            case .app(let bundleID, _, _): bundleID
            }
        }

        var pid: pid_t {
            switch self {
            case .site(_, _, let pid), .app(_, _, let pid): pid
            }
        }
    }

    /// Activé à la main (bouton ✋).
    var isEnabled: Bool = UserDefaults.standard.bool(forKey: "focusGuardEnabled") {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "focusGuardEnabled")
            check()
        }
    }

    /// Activé de lui-même pendant un Pomodoro (hors pause).
    var duringPomodoro: Bool = UserDefaults.standard.object(forKey: "focusGuardDuringPomodoro") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(duringPomodoro, forKey: "focusGuardDuringPomodoro")
            check()
        }
    }

    /// Activé de lui-même pendant un mode Concentration de macOS.
    var duringFocus: Bool = UserDefaults.standard.bool(forKey: "focusGuardDuringFocus") {
        didSet {
            UserDefaults.standard.set(duringFocus, forKey: "focusGuardDuringFocus")
            check()
        }
    }

    @ObservationIgnored var timerController: TimerController?
    @ObservationIgnored var focusMonitor: FocusMonitor?

    /// Le Pomodoro ou la Concentration qui l'active en ce moment, s'il n'est pas activé à la main.
    var automaticReason: String? {
        guard !isEnabled else { return nil }
        if duringPomodoro, let timer = timerController, timer.isActive, !timer.isPaused, timer.kind == .pomodoro {
            return "Pomodoro"
        }
        if duringFocus, let mode = focusMonitor?.activeMode { return mode.name }
        return nil
    }

    /// Le gardien surveille : à la main, ou pendant un Pomodoro ou une Concentration.
    var isActive: Bool { isEnabled || automaticReason != nil }

    /// Depuis quand tu es sur un site interdit (pour les yeux de l'encoche), `nil` sinon.
    private(set) var watchingSince: Date?
    /// La pince est sortie de l'encoche (ses yeux n'y guettent plus).
    private(set) var isClawOut = false
    /// La pince va sortir : le visage sous l'encoche se resserre en elle.
    private(set) var isClawLaunching = false
    /// Onglet attrapé à l'instant : le visage sous l'encoche est content quelques secondes.
    private(set) var isHappy = false
    /// Colère de la pince sur le site en cours : combien de fois tu l'as chassée.
    private(set) var anger = 0

    /// Domaines interdits (« youtube.com » couvre aussi « m.youtube.com »).
    var blockedSites: [String] =
        UserDefaults.standard.stringArray(forKey: "focusGuardSites") ?? FocusGuardRules.defaultSites
    {
        didSet { UserDefaults.standard.set(blockedSites, forKey: "focusGuardSites") }
    }

    /// Apps interdites, par identifiant (« com.spotify.client »).
    var blockedApps: [String] = UserDefaults.standard.stringArray(forKey: "focusGuardApps") ?? [] {
        didSet { UserDefaults.standard.set(blockedApps, forKey: "focusGuardApps") }
    }

    /// Temps passé sur un site ou une app interdits, sans en sortir, avant que la pince arrive.
    /// (Réglable pour les essais : `defaults write com.guillaumeprost.notch focusGuardGraceSeconds 10`.)
    static var gracePeriod: TimeInterval {
        let custom = UserDefaults.standard.double(forKey: "focusGuardGraceSeconds")
        return custom > 0 ? custom : 30
    }

    /// Site ou app interdits au premier plan, et depuis quand (le délai repart de zéro dès qu'on
    /// en sort).
    @ObservationIgnored private var pending: (key: String, since: Date, lastSeen: Date)?

    /// Absence tolérée (lecture ratée, coup d'œil ailleurs) avant de remettre le délai à zéro.
    static let leaveTolerance: TimeInterval = 5

    /// Une fois chassée, la pince revient au bout de ce temps si tu es toujours sur le site :
    /// de plus en plus vite à chaque fois (2 min, 1 min, puis 30 s).
    static func snoozeDuration(anger: Int) -> TimeInterval {
        [2 * 60, 60, 30][min(max(anger - 1, 0), 2)]
    }

    /// Chassée autant de fois, elle ne se laisse plus faire.
    static let maxChases = 2

    @ObservationIgnored private let overlay = GuardianOverlay()
    @ObservationIgnored private var snoozedUntil: [String: Date] = [:]
    @ObservationIgnored private var angerByKey: [String: Int] = [:]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var checking = false

    init() {
        overlay.onFinished = { [weak self] grabbed in
            self?.isClawOut = false
            self?.isClawLaunching = false
            guard grabbed else { return }
            self?.isHappy = true
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2.5))
                self?.isHappy = false
            }
        }
        start()
    }

    // MARK: - Listes

    /// Ajoute un domaine tapé à la main (« https://www.reddit.com/r/… » devient « reddit.com »).
    @discardableResult
    func addSite(_ input: String) -> Bool {
        guard let domain = FocusGuardRules.normalizedDomain(input), !blockedSites.contains(domain) else { return false }
        blockedSites.append(domain)
        return true
    }

    func addApp(_ bundleID: String) {
        guard !blockedApps.contains(bundleID) else { return }
        blockedApps.append(bundleID)
    }

    /// Nom affiché d'une app (« Spotify »), d'après son identifiant.
    static func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    /// Apps ouvertes, à proposer dans la liste (sauf celles déjà interdites et les navigateurs).
    var candidateApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular, let id = app.bundleIdentifier else { return false }
                return id != Bundle.main.bundleIdentifier && !blockedApps.contains(id) && Browser.find(id) == nil
            }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    // MARK: - Surveillance

    private func start() {
        guard timer == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        // Changer d'onglet ne prévient pas : on relit l'adresse régulièrement.
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        check()
    }

    /// Plus de surveillance (désactivé, fin du Pomodoro) : tout est oublié.
    private func reset() {
        pending = nil
        snoozedUntil.removeAll()
        angerByKey.removeAll()
        if watchingSince != nil { watchingSince = nil }
        if anger != 0 { anger = 0 }
        overlay.leave()
    }

    private func check() {
        guard isActive else {
            if pending != nil || !overlay.isIdle || !angerByKey.isEmpty { reset() }
            return
        }
        guard overlay.isIdle, !checking else { return }
        checking = true
        Task {
            defer { checking = false }
            guard isActive, overlay.isIdle else { return }
            let now = Date()
            guard let target = await currentTarget() else {
                // Une lecture ratée (page qui charge, vidéo en plein écran…) ne remet pas le
                // compteur à zéro : seulement si on a vraiment quitté le site quelques secondes.
                if let pending, now.timeIntervalSince(pending.lastSeen) > Self.leaveTolerance {
                    self.pending = nil
                    snoozedUntil.removeAll()
                    angerByKey.removeAll()
                    watchingSince = nil
                    anger = 0
                } else if pending == nil, snoozedUntil.isEmpty {
                    if watchingSince != nil { watchingSince = nil }
                    if anger != 0 { anger = 0 }
                }
                return
            }
            // Un autre site : le répit et la colère de l'ancien sont oubliés.
            snoozedUntil = snoozedUntil.filter { $0.key == target.key }
            angerByKey = angerByKey.filter { $0.key == target.key }
            let currentAnger = angerByKey[target.key] ?? 0
            if anger != currentAnger { anger = currentAnger }
            if let until = snoozedUntil[target.key] {
                guard until <= now else { return }
                // Chassée, elle revient d'elle-même à la fin du répit, sans nouveau délai.
                snoozedUntil[target.key] = nil
                pending = nil
                await intercept(target)
                return
            }
            guard let pending, pending.key == target.key else {
                self.pending = (target.key, now, now)
                watchingSince = now
                return
            }
            self.pending?.lastSeen = now
            if watchingSince != pending.since { watchingSince = pending.since }
            guard now.timeIntervalSince(pending.since) >= Self.gracePeriod else { return }
            self.pending = nil
            watchingSince = nil
            await intercept(target)
        }
    }

    /// Le site ou l'app interdits au premier plan, s'il y en a un.
    private func currentTarget() async -> Target? {
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier else { return nil }
        if blockedApps.contains(id) {
            return .app(bundleID: id, name: app.localizedName ?? id, pid: app.processIdentifier)
        }
        guard let browser = Browser.find(id), !blockedSites.isEmpty else { return nil }
        let url = await browser.frontURL(pid: app.processIdentifier)
        guard let url,
            let host = URL(string: url)?.host(),
            let domain = FocusGuardRules.matchingSite(host: host, in: blockedSites)
        else { return nil }
        return .site(domain: domain, browserID: id, pid: app.processIdentifier)
    }

    private func intercept(_ target: Target) async {
        guard let window = Self.frontWindowFrame(pid: target.pid) else { return }
        // La pince vise l'onglet affiché ; à défaut (app, onglet introuvable), la barre de titre.
        var grabPoint = NSPoint(x: window.midX, y: window.maxY - 14)
        var tab = GuardianOverlay.CarriedTab(title: target.key, size: CGSize(width: 150, height: 28))
        switch target {
        case .site(let domain, let browserID, let pid):
            tab.title = domain
            if let selected = await Browser.find(browserID)?.selectedTab(pid: pid),
                let primaryHeight = NSScreen.screens.first?.frame.height
            {
                let frame = ScreenLayout.quartzFrame(selected.frame, primaryHeight: primaryHeight)
                grabPoint = NSPoint(x: frame.midX, y: frame.midY)
                if !selected.title.isEmpty { tab.title = selected.title }
                tab.size = CGSize(width: min(max(frame.width, 110), 220), height: min(max(frame.height, 24), 34))
            }
        case .app(_, let name, _):
            tab.title = name
        }
        guard isActive, overlay.isIdle else { return }
        watchingSince = nil
        isClawLaunching = true
        try? await Task.sleep(for: .seconds(0.45))
        guard isActive, overlay.isIdle else {
            isClawLaunching = false
            return
        }
        // Le visage reste resserré jusqu'au retour de la pince (sinon il se redéploierait
        // pendant qu'il disparaît).
        isClawOut = true
        let anger = angerByKey[target.key] ?? 0
        overlay.intercept(
            tab: tab,
            grabPoint: grabPoint,
            anger: anger,
            unchasable: anger >= Self.maxChases,
            // Toujours là au moment d'attraper ? Sinon elle remonte sans rien fermer.
            stillThere: { [weak self] in await self?.currentTarget() == target },
            close: { [weak self] in
                Self.close(target)
                // Onglet attrapé : sa colère retombe.
                self?.angerByKey[target.key] = nil
                self?.anger = 0
            },
            chased: { [weak self] in
                guard let self else { return }
                let anger = (angerByKey[target.key] ?? 0) + 1
                angerByKey[target.key] = anger
                self.anger = anger
                snoozedUntil[target.key] = Date().addingTimeInterval(Self.snoozeDuration(anger: anger))
            }
        )
    }

    private static func close(_ target: Target) {
        switch target {
        case .app(let bundleID, _, _):
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
        case .site(_, _, let pid):
            // ⌘W : ferme l'onglet affiché, dans tous les navigateurs. La touche « W » dépend
            // du clavier : en AZERTY, la touche 13 est le « Z » (⌘Z rouvrait un onglet).
            AX.press(key: Self.keyCode(for: "w") ?? 13, flags: .maskCommand, to: pid)
        }
    }

    /// Touche qui tape `character` avec la disposition de clavier en cours.
    static func keyCode(for character: Character) -> CGKeyCode? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        let target = String(character)
        return data.withUnsafeBytes { buffer -> CGKeyCode? in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            for code in 0..<CGKeyCode(128) {
                var deadKeys: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
                if status == noErr, String(utf16CodeUnits: chars, count: length) == target { return code }
            }
            return nil
        }
    }

    /// Cadre de la fenêtre au premier plan de l'app, en coordonnées de l'écran (origine en bas).
    private static func frontWindowFrame(pid: pid_t) -> CGRect? {
        guard
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
            let window = windows.first(where: {
                $0[kCGWindowOwnerPID as String] as? pid_t == pid && $0[kCGWindowLayer as String] as? Int == 0
            }),
            let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsDict),
            let primaryHeight = NSScreen.screens.first?.frame.height
        else { return nil }
        return ScreenLayout.quartzFrame(bounds, primaryHeight: primaryHeight)
    }
}

/// Navigateurs dont on lit l'adresse par l'Accessibilité (déjà autorisée pour Encoche) :
/// pas besoin de l'autorisation « Automatisation », dont la demande bloquait la lecture.
struct Browser {
    let bundleID: String
    /// Navigateurs Chromium : leur contenu web n'est exposé qu'à la demande.
    let chromium: Bool

    static let all: [Browser] = [
        Browser(bundleID: "com.apple.Safari", chromium: false),
        Browser(bundleID: "com.apple.SafariTechnologyPreview", chromium: false),
        Browser(bundleID: "com.google.Chrome", chromium: true),
        Browser(bundleID: "com.brave.Browser", chromium: true),
        Browser(bundleID: "com.microsoft.edgemac", chromium: true),
        Browser(bundleID: "company.thebrowser.Browser", chromium: true),
        Browser(bundleID: "com.vivaldi.Vivaldi", chromium: true),
        Browser(bundleID: "com.operasoftware.Opera", chromium: true),
    ]

    static func find(_ bundleID: String) -> Browser? { all.first { $0.bundleID == bundleID } }

    /// Adresse de l'onglet affiché dans la fenêtre au premier plan (hors du fil principal :
    /// l'Accessibilité peut être lente).
    func frontURL(pid: pid_t) async -> String? {
        let manual = chromium
        return await Task.detached { Self.readURL(pid: pid, manual: manual) }.value
    }

    /// Onglet sélectionné : son cadre (coordonnées Quartz) et son titre, pour que la pince
    /// l'attrape vraiment.
    func selectedTab(pid: pid_t) async -> (frame: CGRect, title: String)? {
        let manual = chromium
        return await Task.detached { Self.readSelectedTab(pid: pid, manual: manual) }.value
    }

    private nonisolated static func readSelectedTab(pid: pid_t, manual: Bool) -> (frame: CGRect, title: String)? {
        let app = AX.app(pid, manual: manual)
        guard let window = AX.element(app, kAXFocusedWindowAttribute) ?? AX.mainWindow(of: app),
            let tab = AX.first(
                in: window, maxDepth: 14, skipping: ["AXWebArea", "AXScrollArea"],
                where: { element in
                    guard AX.string(element, kAXSubroleAttribute) == "AXTabButton" else { return false }
                    var value: AnyObject?
                    AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
                    if (value as? NSNumber)?.boolValue == true { return true }
                    AXUIElementCopyAttributeValue(element, kAXSelectedAttribute as CFString, &value)
                    return (value as? NSNumber)?.boolValue == true
                })
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(tab, kAXPositionAttribute as CFString, &value) == .success,
            let positionValue = value, AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
            AXUIElementCopyAttributeValue(tab, kAXSizeAttribute as CFString, &value) == .success,
            let sizeValue = value, AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        return (CGRect(origin: position, size: size), AX.label(of: tab))
    }

    private nonisolated static func readURL(pid: pid_t, manual: Bool) -> String? {
        let app = AX.app(pid, manual: manual)
        guard let window = AX.element(app, kAXFocusedWindowAttribute) ?? AX.mainWindow(of: app),
            let webArea = AX.first(in: window, maxDepth: 30, where: { AX.role($0) == "AXWebArea" })
        else { return nil }
        var value: AnyObject?
        AXUIElementCopyAttributeValue(webArea, kAXURLAttribute as CFString, &value)
        return (value as? URL)?.absoluteString
    }
}

/// Règles du gardien, sans interface (testées).
enum FocusGuardRules {
    static let defaultSites = [
        "youtube.com", "x.com", "twitter.com", "reddit.com", "instagram.com", "facebook.com", "tiktok.com",
    ]

    /// « https://www.Reddit.com/r/swift » → « reddit.com » ; `nil` si ce n'est pas un domaine.
    static func normalizedDomain(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let range = text.range(of: "://") { text = String(text[range.upperBound...]) }
        text = String(text.prefix { $0 != "/" && $0 != "?" && $0 != "#" && $0 != ":" })
        if text.hasPrefix("www.") { text.removeFirst(4) }
        let allowed = CharacterSet.lowercaseLetters.union(.decimalDigits).union(CharacterSet(charactersIn: ".-"))
        guard text.contains("."), !text.hasPrefix("."), !text.hasSuffix("."),
            text.unicodeScalars.allSatisfy(allowed.contains)
        else { return nil }
        return text
    }

    /// Le domaine de la liste qui couvre cette adresse (lui-même ou un sous-domaine).
    static func matchingSite(host: String, in sites: [String]) -> String? {
        let host = host.lowercased()
        return sites.first { host == $0 || host.hasSuffix("." + $0) }
    }
}

/// Bouton à côté du minuteur : active ou désactive le gardien (la pince).
struct FocusGuardButton: View {
    @Environment(FocusGuard.self) private var focusGuard
    @State private var hovering = false

    var body: some View {
        let isOn = focusGuard.isActive
        let automatic = focusGuard.automaticReason
        Button {
            focusGuard.isEnabled.toggle()
        } label: {
            Image(systemName: isOn ? "hand.raised.fill" : "hand.raised")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn ? Color.orange : Color.primary)
                .frame(width: 26, height: 22)
                .background(Capsule().fill(isOn ? Color.orange.opacity(0.18) : .primary.opacity(hovering ? 0.12 : 0)))
                // Activé par un Pomodoro ou une Concentration : un liseré en pointillé.
                .overlay {
                    if automatic != nil {
                        Capsule().strokeBorder(Color.orange.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    }
                }
                .opacity(hovering || isOn ? 1 : 0.6)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(
            automatic.map { "Gardien activé pendant : \($0). Cliquer pour l'activer en permanence." }
                ?? (focusGuard.isEnabled
                    ? "Gardien activé : la pince ferme les sites interdits après 30 s. Cliquer pour désactiver."
                    : "Activer le gardien anti-distraction"))
    }
}
