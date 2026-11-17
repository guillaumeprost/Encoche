import SwiftUI

/// Le petit personnage en pixels de Claude Code, animé selon ce qu'il fait.
///
/// Le motif reprend celui que Claude Code affiche dans le terminal (blocs « ▐▛███▜▌ »).
/// Dans le terminal, un caractère fait deux pixels de large et deux de haut, chacun deux fois
/// plus haut que large : on garde ces proportions.
struct ClaudeMascot: View {
    enum Mood: Equatable {
        /// Au repos : il cligne des yeux de temps en temps.
        case idle
        /// Au travail : il trottine.
        case working
        /// Il t'attend : il agite les bras.
        case waiting
        /// Tâche terminée : il saute, les deux bras en l'air.
        case celebrating
        /// Une commande ou un outil vient d'échouer : il tremble, les yeux plissés.
        case worried
        /// Session fermée : yeux fermés, il respire lentement.
        case sleeping
    }

    var mood: Mood = .idle
    var color: Color = .claude

    /// Largeur et hauteur du motif, en pixels.
    static let columns = 18
    static let rows = 5
    /// Un pixel du terminal est deux fois plus haut que large.
    static let aspectRatio = CGFloat(columns) / CGFloat(rows * 2)

    /// Au repos, un clignement toutes les 4 secondes ; ailleurs, une image toutes les 0,12 s.
    nonisolated fileprivate static let blinkPeriod: TimeInterval = 4
    nonisolated fileprivate static let blinkLength: TimeInterval = 0.15
    private static let step: TimeInterval = 0.12

    var body: some View {
        // Au repos, on ne redessine qu'aux deux moments du clignement (et non en continu).
        TimelineView(schedule) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let tick = Int(time / Self.step)
            let blinking =
                mood == .sleeping
                || (mood == .idle && time.truncatingRemainder(dividingBy: Self.blinkPeriod) < Self.blinkLength)
            Canvas { canvas, size in
                draw(in: &canvas, size: size, tick: tick, blinking: blinking)
            }
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .accessibilityLabel("Claude Code")
    }

    /// Au repos, on ne redessine qu'aux deux moments du clignement ; endormi, une respiration
    /// toutes les 1,2 s ; sinon une image toutes les 0,12 s.
    private var schedule: AnyTimelineSchedule {
        switch mood {
        case .idle: AnyTimelineSchedule(BlinkSchedule())
        case .sleeping: AnyTimelineSchedule(.periodic(from: .now, by: 1.2))
        default: AnyTimelineSchedule(.periodic(from: .now, by: Self.step))
        }
    }

    // MARK: - Dessin

    private func draw(in canvas: inout GraphicsContext, size: CGSize, tick: Int, blinking: Bool) {
        let pixelWidth = size.width / CGFloat(Self.columns)
        let pixelHeight = size.height / CGFloat(Self.rows)
        // Au travail, il rebondit d'un tiers de pixel à chaque pas ; content, il saute plus haut ;
        // endormi, il respire.
        var bounce: CGFloat = 0
        var shake: CGFloat = 0
        switch mood {
        case .working: bounce = tick % 2 == 0 ? -pixelHeight * 0.35 : 0
        case .celebrating: bounce = [0, -0.5, -0.9, -0.5][tick % 4] * pixelHeight
        case .sleeping: bounce = (tick / 10) % 2 == 0 ? pixelHeight * 0.15 : 0
        case .worried: shake = tick % 2 == 0 ? -pixelWidth * 0.3 : pixelWidth * 0.3
        default: break
        }

        // Tous les pixels forment un seul tracé, rempli d'un coup : pas de fines lignes entre eux.
        var shape = Path()
        func fill(_ x: Int, _ y: Int, dy: CGFloat = 0) {
            shape.addRect(
                CGRect(
                    x: CGFloat(x) * pixelWidth + shake,
                    y: CGFloat(y) * pixelHeight + dy,
                    width: pixelWidth,
                    height: pixelHeight
                ))
        }

        // Corps : deux lignes pleines ; les yeux sont des trous, refermés quand il cligne.
        for x in 3...14 { fill(x, 0, dy: bounce) }
        for x in 3...14 where blinking || (x != 5 && x != 12) { fill(x, 1, dy: bounce) }
        // Inquiet : les yeux se plissent (un demi-pixel refermé).
        if mood == .worried {
            for x in [5, 12] { fill(x, 1, dy: bounce - pixelHeight * 0.5) }
        }

        // Bras : en attente, ils se lèvent l'un après l'autre ; content, les deux à la fois.
        let leftUp = (mood == .waiting && tick % 4 < 2) || (mood == .celebrating && tick % 4 != 0)
        let rightUp = (mood == .waiting && tick % 4 >= 2) || (mood == .celebrating && tick % 4 != 0)
        for x in 3...14 { fill(x, 2, dy: bounce) }
        fill(1, leftUp ? 1 : 2, dy: bounce)
        fill(2, 2, dy: bounce)
        fill(15, 2, dy: bounce)
        fill(16, rightUp ? 1 : 2, dy: bounce)
        for x in 3...14 { fill(x, 3, dy: bounce) }

        // Pattes : au travail, une paire sur deux se lève à chaque pas.
        let legs = [4, 6, 11, 13]
        for (index, x) in legs.enumerated() {
            let lifted = mood == .working && (index % 2 == tick % 2)
            // En sautant, les pattes suivent le corps.
            let jump = mood == .celebrating ? bounce : 0
            fill(x, 4, dy: lifted ? -pixelHeight * 0.45 : jump)
        }
        canvas.fill(shape, with: .color(color))
    }
}

#Preview {
    VStack(spacing: 20) {
        ClaudeMascot(mood: .idle).frame(width: 90)
        ClaudeMascot(mood: .working).frame(width: 90)
        ClaudeMascot(mood: .waiting).frame(width: 90)
        ClaudeMascot(mood: .celebrating).frame(width: 90)
        ClaudeMascot(mood: .worried).frame(width: 90)
        ClaudeMascot(mood: .sleeping).frame(width: 90)
    }
    .padding(30)
    .background(.black)
}

/// Moments où le personnage au repos change d'image : début et fin de chaque clignement.
private struct BlinkSchedule: TimelineSchedule {
    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        let period = ClaudeMascot.blinkPeriod
        let length = ClaudeMascot.blinkLength
        let start = startDate.timeIntervalSinceReferenceDate
        var cycle = (start / period).rounded(.down)
        var closing = true
        return AnyIterator {
            defer {
                if !closing { cycle += 1 }
                closing.toggle()
            }
            return Date(timeIntervalSinceReferenceDate: cycle * period + (closing ? 0 : length))
        }
    }
}

/// Planning de TimelineView choisi à l'exécution.
private struct AnyTimelineSchedule: TimelineSchedule {
    private let makeEntries: (Date, TimelineScheduleMode) -> AnyIterator<Date>

    init<S: TimelineSchedule>(_ schedule: S) {
        makeEntries = { start, mode in
            var iterator = schedule.entries(from: start, mode: mode).makeIterator()
            return AnyIterator { iterator.next() }
        }
    }

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        makeEntries(startDate, mode)
    }
}
