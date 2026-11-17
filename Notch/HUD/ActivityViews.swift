import SwiftUI

/// Activités en direct autour de l'encoche repliée, par ordre de priorité.
enum LiveActivity: Hashable {
    case call, claudeWaiting, privacy, meeting, timer, download, claudeWorking, music, focus

    /// Onglet ouvert d'un clic sur l'activité.
    var tab: NotchTab {
        switch self {
        case .music: .music
        case .claudeWaiting, .claudeWorking: .claude
        case .meeting: .calendar
        case .call, .privacy, .timer, .download, .focus: .home
        }
    }

    /// Activités en cours, la plus importante d'abord.
    @MainActor
    static func active(
        settings: AppSettings, claudeCode: ClaudeCodeMonitor, privacy: PrivacyMonitor,
        downloads: DownloadMonitor, music: MusicController,
        calendar: CalendarController, timer: TimerController, focus: FocusMonitor, calls: CallMonitor
    ) -> [LiveActivity] {
        var list: [LiveActivity] = []
        if calls.isActive { list.append(.call) }
        // Une session t'attend, ou vient de finir (le personnage saute de joie quelques secondes).
        if claudeCode.needsAttention || (settings.showClaudeActivity && claudeCode.isCelebrating) {
            list.append(.claudeWaiting)
        }
        if privacy.isActive { list.append(.privacy) }
        if settings.showMeetingActivity, calendar.upcomingMeeting != nil { list.append(.meeting) }
        if timer.isActive { list.append(.timer) }
        if settings.showDownloadActivity, downloads.showsActivity { list.append(.download) }
        if settings.showClaudeActivity, claudeCode.workingSession != nil { list.append(.claudeWorking) }
        if music.showsActivity { list.append(.music) }
        if settings.showFocusActivity, focus.activeMode != nil { list.append(.focus) }
        return list
    }
}

/// Deuxième activité, dans une petite bulle à droite de l'encoche (comme sur iPhone).
struct ActivityBubble: View {
    @Environment(PrivacyMonitor.self) private var privacy
    @Environment(MeetingController.self) private var meeting
    @Environment(DownloadMonitor.self) private var downloads
    @Environment(MusicController.self) private var music
    @Environment(CalendarController.self) private var calendar
    @Environment(TimerController.self) private var timer
    @Environment(FocusMonitor.self) private var focus
    @Environment(ClaudeCodeMonitor.self) private var claudeCode
    let activity: LiveActivity

    /// Contenu seul : le fond (et la division depuis l'encoche) est dessiné par `MitosisBubble`.
    var body: some View { content }

    @ViewBuilder
    private var content: some View {
        switch activity {
        case .call:
            Image(systemName: "phone.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)
        case .claudeWaiting:
            ClaudeMascot(mood: claudeCode.needsAttention ? .waiting : .celebrating)
                .frame(width: 19)
        case .privacy:
            let indicator = PrivacyIndicator(privacy: privacy, meeting: meeting)
            Image(systemName: indicator.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(indicator.color)
        case .download:
            ZStack {
                ProgressRing(fraction: downloads.fraction, tint: .blue)
                Image(systemName: "arrow.down").font(.system(size: 7, weight: .heavy)).foregroundStyle(.blue)
            }
            .frame(width: 17, height: 17)
        case .claudeWorking:
            ClaudeMascot(mood: claudeCode.workingSession.map(claudeCode.mood(of:)) ?? .working)
                .frame(width: 19)
        case .meeting:
            if let meeting = calendar.upcomingMeeting {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    ZStack {
                        ProgressRing(
                            fraction: max(meeting.start.timeIntervalSince(context.date), 0) / CalendarController.countdownWindow,
                            tint: meeting.color
                        )
                        Text(MeetingCountdown.short(until: meeting.start, now: context.date))
                            .font(.system(size: 7.5, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    .frame(width: 20, height: 20)
                }
            }
        case .timer:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let tint = timer.tint(remaining: timer.remaining(at: context.date))
                ZStack {
                    ProgressRing(fraction: timer.fraction(at: context.date), tint: tint)
                    Image(systemName: timer.isPaused ? "pause.fill" : timer.kind.symbol)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 18, height: 18)
            }
        case .focus:
            Image(systemName: focus.activeMode?.symbol ?? "moon.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.indigo)
        case .music:
            Artwork(image: music.artwork, cornerRadius: 5)
                .frame(width: 21, height: 21)
        }
    }
}

/// Deuxième activité qui se détache de l'encoche comme une cellule qui se divise : la bulle
/// sort du bord, reste reliée par un col qui s'étire puis se rompt, et se pose avec un rebond.
struct MitosisBubble: View {
    let activity: LiveActivity
    let size: CGFloat
    /// Distance entre le bord de l'encoche et la bulle.
    let gap: CGFloat
    @State private var progress: Double = 0
    /// Ressort arrêté : la forme nette remplace l'effet gluant (pas avant, sinon les deux
    /// alternent pendant que le ressort oscille autour de sa position finale).
    @State private var settled = false

    var body: some View {
        MitosisShape(progress: progress, settled: settled, size: size, gap: gap) {
            ActivityBubble(activity: activity)
        }
        .frame(width: MitosisMetrics.overlap + gap + size, height: size)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.58)) {
                progress = 1
            } completion: {
                settled = true
            }
        }
    }
}

/// Forme de la division. Pendant l'animation : flou puis seuil de transparence (effet
/// « gluant »), qui soude la bulle au bord de l'encoche tant qu'elles sont proches.
/// Une fois posée : carré arrondi net, avec un fin liseré lumineux vers le bas.
private enum MitosisMetrics {
    /// Largeur du bord de l'encoche repris dans la forme, pour que le col y prenne racine.
    static let overlap: CGFloat = 6
    /// Marge autour du dessin : le flou ne doit pas être coupé par le cadre.
    static let margin: CGFloat = 14
}

private struct MitosisShape<Content: View>: View, Animatable {
    private static var overlap: CGFloat { MitosisMetrics.overlap }
    private static var margin: CGFloat { MitosisMetrics.margin }

    var progress: Double
    let settled: Bool
    let size: CGFloat
    let gap: CGFloat
    /// Contenu de la bulle (pochette, icône) : il suit la bulle pendant toute la division.
    @ViewBuilder let content: Content

    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private var bubbleShape: RoundedRectangle { RoundedRectangle(cornerRadius: 9, style: .continuous) }

    /// Bord gauche de la bulle (avant mise à l'échelle) et taille, à cet instant de la division.
    /// La bulle part de l'intérieur de l'encoche et grossit en s'éloignant (le ressort peut
    /// la faire dépasser un peu).
    private var bubbleX: CGFloat {
        let start = Self.overlap - size
        let end = Self.overlap + gap
        return start + (end - start) * progress
    }

    private var bubbleSide: CGFloat { size * (0.4 + 0.6 * min(progress, 1)) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            shape
            content
                .frame(width: size, height: size)
                .scaleEffect(bubbleSide / size)
                .offset(x: bubbleX)
                // Apparaît pendant qu'elle se détache, encore reliée par le col.
                .opacity(min(max((progress - 0.3) / 0.4, 0), 1))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var shape: some View {
        if settled {
            bubbleShape
                .fill(.black)
                .overlay(bubbleShape.strokeBorder(rim, lineWidth: 1))
                .frame(width: size, height: size)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            Canvas { context, _ in
                let margin = Self.margin
                context.addFilter(.alphaThreshold(min: 0.5, color: .black))
                context.addFilter(.blur(radius: 6))
                context.drawLayer { layer in
                    // Bord de l'encoche, d'où part la bulle : au milieu de la hauteur et sans
                    // dépasser le bord, pour ne pas remplir les coins arrondis de l'encoche.
                    layer.fill(
                        Path(CGRect(x: 0, y: margin + size * 0.2, width: margin + Self.overlap, height: size * 0.6)),
                        with: .color(.black))
                    let side = bubbleSide
                    let x = margin + bubbleX + (size - side) / 2
                    let rect = CGRect(x: x, y: margin + (size - side) / 2, width: side, height: side)
                    layer.fill(Path(roundedRect: rect, cornerRadius: 9, style: .continuous), with: .color(.black))
                }
            }
            .padding(-Self.margin)
        }
    }

    /// Liseré comme le verre noir de l'encoche ouverte : invisible en haut, plus clair en bas.
    private var rim: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(0), location: 0.35),
                .init(color: .white.opacity(0.22), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Disposition des activités repliées : un élément de chaque côté de l'encoche.
struct CollapsedActivityLayout<Leading: View, Trailing: View>: View {
    let slotWidth: CGFloat
    let leading: Leading
    let trailing: Trailing

    init(slotWidth: CGFloat, @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.slotWidth = slotWidth
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 0) {
            leading.frame(width: slotWidth)
            Spacer(minLength: 0)
            trailing.frame(width: slotWidth)
        }
    }
}

/// Anneau de progression des activités en direct.
struct ProgressRing: View {
    /// Entre 0 et 1, ou `nil` pour un anneau qui tourne (durée inconnue).
    let fraction: Double?
    var tint: Color = .white
    var lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.25), lineWidth: lineWidth)
            if let fraction {
                Circle()
                    .trim(from: 0, to: min(max(fraction, 0.02), 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.snappy, value: fraction)
            } else {
                TimelineView(.animation) { context in
                    let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(angle))
                }
            }
        }
    }
}

/// Claude Code travaille : son personnage qui trottine à gauche, l'avancement de son plan à droite.
struct CollapsedClaudeWorkingView: View {
    @Environment(ClaudeCodeMonitor.self) private var monitor
    let slotWidth: CGFloat

    var body: some View {
        let session = monitor.workingSession
        CollapsedActivityLayout(slotWidth: slotWidth) {
            ClaudeMascot(mood: session.map(monitor.mood(of:)) ?? .working)
                .frame(width: 28)
        } trailing: {
            HStack(spacing: 3) {
                // Avancement du plan, ou anneau qui tourne sans plan.
                ProgressRing(fraction: session?.planFraction, tint: .claude)
                    .frame(width: 15, height: 15)
                // Plusieurs sessions au travail en même temps.
                if monitor.workingCount > 1 {
                    Text("\(monitor.workingCount)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.claude)
                        .contentTransition(.numericText())
                }
            }
        }
        .help(help(session))
    }

    private func help(_ session: ClaudeCodeSession?) -> String {
        guard let session else { return "Claude travaille" }
        var text = "\(session.title ?? session.projectName) · \(session.detail ?? "en cours")"
        if let start = session.workStartedAt { text += " · \(ClaudeCodeSession.elapsed(since: start))" }
        if monitor.workingCount > 1 { text += "\n\(monitor.workingCount) sessions au travail" }
        return text
    }
}

/// Téléchargement en cours : anneau à gauche, pourcentage à droite.
struct CollapsedDownloadView: View {
    @Environment(DownloadMonitor.self) private var downloads
    let slotWidth: CGFloat

    var body: some View {
        CollapsedActivityLayout(slotWidth: slotWidth) {
            ZStack {
                if downloads.finishedName != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    ProgressRing(fraction: downloads.fraction, tint: .blue)
                        .frame(width: 15, height: 15)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(.blue)
                }
            }
        } trailing: {
            Group {
                if downloads.finishedName != nil {
                    Image(systemName: "folder.fill").foregroundStyle(.blue)
                } else {
                    Text(downloads.fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "…")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText())
                        .foregroundStyle(.white)
                        .padding(.trailing, 4)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                }
            }
            .font(.system(size: 12))
        }
        .animation(.snappy, value: downloads.finishedName)
        .help(downloads.finishedName.map { "\($0) téléchargé" } ?? downloads.currentName ?? "Téléchargement")
        .onTapGesture { downloads.revealDownloads() }
    }
}

/// Appareil Bluetooth connecté ou déconnecté (AirPods, clavier…), sous l'encoche.
struct DeviceHUDView: View {
    @Environment(BluetoothMonitor.self) private var bluetooth

    var body: some View {
        if let event = bluetooth.lastEvent {
            HStack(spacing: 8) {
                Image(systemName: event.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(event.isConnected ? .white : .white.opacity(0.5))
                    .frame(width: 18)
                Text(event.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let battery = event.battery, event.isConnected {
                    HStack(spacing: 3) {
                        Image(systemName: BatteryMonitor.symbol(forLevel: battery))
                            .symbolRenderingMode(.hierarchical)
                        Text("\(battery) %")
                    }
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(battery <= 20 ? .red : .white)
                    .transition(.opacity)
                } else {
                    Text(event.isConnected ? "Connecté" : "Déconnecté")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(event.isConnected ? .green : .white.opacity(0.5))
                }
            }
            .foregroundStyle(.white)
            .animation(.snappy, value: event.battery)
        }
    }

}

// MARK: - Réunion, minuteur, Concentration

/// Temps restant avant une réunion, en version courte (« 8 min », « 45 s »).
enum MeetingCountdown {
    static func short(until start: Date, now: Date) -> String {
        let seconds = max(Int(start.timeIntervalSince(now).rounded(.up)), 0)
        return seconds >= 60 ? "\((seconds + 59) / 60) min" : "\(seconds) s"
    }
}

/// Réunion dans moins de 10 minutes : icône à gauche, compte à rebours à droite.
struct CollapsedMeetingView: View {
    @Environment(CalendarController.self) private var calendar
    let slotWidth: CGFloat

    var body: some View {
        if let meeting = calendar.upcomingMeeting {
            CollapsedActivityLayout(slotWidth: slotWidth) {
                Image(systemName: meeting.meetingURL != nil ? "video.fill" : "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(meeting.color)
            } trailing: {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(MeetingCountdown.short(until: meeting.start, now: context.date))
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(meeting.color)
                        .contentTransition(.numericText())
                        // Un peu d'air avant le bord arrondi de l'encoche.
                        .padding(.trailing, 5)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                }
            }
            .help("\(meeting.title) à \(meeting.start.formatted(date: .omitted, time: .shortened))")
        }
    }
}

/// Minuteur en cours : anneau et type à gauche, temps restant à droite, et une fine barre
/// de progression sous l'encoche. Orange au travail, turquoise en pause, rouge la dernière minute.
struct CollapsedTimerView: View {
    @Environment(TimerController.self) private var timer
    let slotWidth: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = timer.remaining(at: context.date)
            let tint = timer.tint(remaining: remaining)
            let seconds = Int(remaining.rounded(.up))
            let finalMinute = seconds <= 60 && !timer.isPaused
            ZStack(alignment: .bottom) {
                CollapsedActivityLayout(slotWidth: slotWidth) {
                    ZStack {
                        ProgressRing(fraction: timer.fraction(at: context.date), tint: tint, lineWidth: 2.5)
                        Image(systemName: timer.isPaused ? "pause.fill" : timer.kind.symbol)
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(tint)
                    }
                    .frame(width: 19, height: 19)
                } trailing: {
                    Text(finalMinute ? "\(seconds)" : Clock.text(seconds))
                        .font(.system(size: finalMinute ? 13 : 11.5, weight: .bold).monospacedDigit())
                        .foregroundStyle(timer.isPaused ? Color.white.opacity(0.45) : tint)
                        .contentTransition(.numericText(countsDown: true))
                        .opacity(finalMinute && seconds % 2 == 0 ? 0.7 : 1)
                        // Un peu d'air avant le bord arrondi de l'encoche.
                        .padding(.trailing, 5)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                }
                // Avancement, sous l'encoche : la barre se vide jusqu'à la fin.
                GeometryReader { geometry in
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(tint)
                                .frame(width: geometry.size.width * timer.fraction(at: context.date))
                        }
                }
                .frame(height: 2.5)
                .padding(.horizontal, slotWidth + 6)
                .padding(.bottom, 2)
            }
            .animation(.linear(duration: 1), value: seconds)
        }
        .help(timer.kind.label + (timer.isPaused ? " (en pause)" : ""))
    }
}

/// Mode Concentration actif : son symbole à gauche de l'encoche.
/// Le visage de la pince, sous l'encoche repliée et sur toute sa largeur. Ses yeux suivent le
/// curseur et clignent ; sur un site interdit, ils se plissent (orange, puis rouges une fois
/// chassée) et une barre se vide jusqu'à ce que la pince sorte ; contents après une prise.
struct GuardianPeek: View {
    @Environment(FocusGuard.self) private var guardian
    @State private var face = GuardianFace()
    /// Largeur du corps de l'encoche (sans ses évasements du haut).
    let width: CGFloat

    private static let height: CGFloat = 30
    /// Hauteur cachée sous l'encoche : elle comble ses coins arrondis du bas, pour que le
    /// visage la prolonge sans couture.
    static let overlap: CGFloat = 14
    /// Distance dont il remonte pour se cacher derrière l'encoche.
    static let travel: CGFloat = height + 4

    var body: some View {
        let launching = guardian.isClawLaunching
        ZStack(alignment: .bottom) {
            UnevenRoundedRectangle(bottomLeadingRadius: 13, bottomTrailingRadius: 13, style: .continuous)
                .fill(.black)
            GuardianEyes(
                style: launching ? .focused : style,
                color: GuardianEyes.color(anger: guardian.anger),
                scale: 1.5,
                spacing: launching ? 18 : width * 0.26,
                blinking: face.blinking && !launching
            )
            // Au départ de la pince, les yeux se rejoignent au milieu…
            .offset(x: launching ? 0 : face.look.width * width * 0.07, y: face.look.height * 3)
            .animation(.easeOut(duration: 0.25), value: face.look)
            .padding(.bottom, guardian.watchingSince == nil ? 9 : 11)
            if let since = guardian.watchingSince {
                // Seule la barre se redessine en continu, et seulement pendant le décompte.
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    let left = max(FocusGuard.gracePeriod - context.date.timeIntervalSince(since), 0)
                    Capsule()
                        .fill(GuardianEyes.color(anger: max(guardian.anger, 1)))
                        .frame(width: width * 0.4 * left / FocusGuard.gracePeriod, height: 2)
                        .frame(width: width * 0.4)
                        .animation(.linear(duration: 0.25), value: left)
                }
                .padding(.bottom, 4)
            }
        }
        .frame(width: width, height: Self.height + Self.overlap)
        // …et le visage remonte derrière l'encoche, d'où la pince va tomber.
        .offset(y: launching ? -Self.travel : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: guardian.watchingSince == nil)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: guardian.anger)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: guardian.isHappy)
        .animation(.easeIn(duration: 0.35), value: launching)
        .allowsHitTesting(false)
        .onAppear { face.start() }
        .onDisappear { face.stop() }
    }

    private var style: GuardianEyes.Style {
        if guardian.isHappy { return .happy }
        if guardian.anger > 0 { return .angry }
        return guardian.watchingSince != nil ? .focused : .normal
    }
}

/// Regard et clignements du visage. Ne change (et ne fait redessiner) que quand le curseur
/// bouge vraiment ou que les yeux clignent : le visage ne coûte presque rien au repos.
@Observable
@MainActor
final class GuardianFace {
    /// Direction du curseur vu de l'encoche : `width` de -1 (à gauche) à 1, `height` de 0 (en
    /// haut) à 1 (en bas de l'écran), par crans.
    private(set) var look: CGSize = .zero
    private(set) var blinking = false

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var nextBlink = Date().addingTimeInterval(3)

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func update() {
        let now = Date()
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let dx = min(max((mouse.x - screen.frame.midX) / (screen.frame.width / 2), -1), 1)
            let dy = min(max((screen.frame.maxY - mouse.y) / screen.frame.height, 0), 1)
            let new = CGSize(width: (dx * 12).rounded() / 12, height: (dy * 6).rounded() / 6)
            if new != look { look = new }
        }
        // Clignement : 0,15 s, toutes les 3 à 6 secondes, parfois double.
        if blinking, now >= nextBlink.addingTimeInterval(0.15) {
            blinking = false
            nextBlink = now.addingTimeInterval(Double.random(in: 0...1) < 0.2 ? 0.25 : .random(in: 3...6))
        } else if !blinking, now >= nextBlink {
            blinking = true
        }
    }
}

struct CollapsedFocusView: View {
    @Environment(FocusMonitor.self) private var focus
    let slotWidth: CGFloat

    var body: some View {
        CollapsedActivityLayout(slotWidth: slotWidth) {
            Image(systemName: focus.activeMode?.symbol ?? "moon.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.indigo)
        } trailing: {
            Color.clear
        }
        .help(focus.activeMode?.name ?? "Concentration")
    }
}
