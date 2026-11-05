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
    }

    var mood: Mood = .idle
    var color: Color = .claude

    /// Largeur et hauteur du motif, en pixels.
    static let columns = 18
    static let rows = 5
    /// Un pixel du terminal est deux fois plus haut que large.
    static let aspectRatio = CGFloat(columns) / CGFloat(rows * 2)

    var body: some View {
        TimelineView(.periodic(from: .now, by: mood == .idle ? 0.15 : 0.12)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / (mood == .idle ? 0.15 : 0.12))
            Canvas { canvas, size in
                draw(in: &canvas, size: size, tick: tick)
            }
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .accessibilityLabel("Claude Code")
    }

    // MARK: - Dessin

    private func draw(in canvas: inout GraphicsContext, size: CGSize, tick: Int) {
        let pixelWidth = size.width / CGFloat(Self.columns)
        let pixelHeight = size.height / CGFloat(Self.rows)
        // Au travail, il rebondit d'un demi-pixel à chaque pas.
        let bounce: CGFloat = mood == .working && tick % 2 == 0 ? -pixelHeight * 0.35 : 0

        // Tous les pixels forment un seul tracé, rempli d'un coup : pas de fines lignes entre eux.
        var shape = Path()
        func fill(_ x: Int, _ y: Int, _: Color, dy: CGFloat = 0) {
            shape.addRect(CGRect(
                x: CGFloat(x) * pixelWidth,
                y: CGFloat(y) * pixelHeight + dy,
                width: pixelWidth,
                height: pixelHeight
            ))
        }

        // Corps : deux lignes pleines ; les yeux sont des trous, refermés quand il cligne.
        let blinking = mood != .working && tick % 28 == 0
        for x in 3...14 { fill(x, 0, color, dy: bounce) }
        for x in 3...14 where blinking || (x != 5 && x != 12) { fill(x, 1, color, dy: bounce) }

        // Bras : en attente, ils se lèvent l'un après l'autre.
        let leftUp = mood == .waiting && tick % 4 < 2
        let rightUp = mood == .waiting && tick % 4 >= 2
        for x in 3...14 { fill(x, 2, color, dy: bounce) }
        fill(1, leftUp ? 1 : 2, color, dy: bounce)
        fill(2, 2, color, dy: bounce)
        fill(15, 2, color, dy: bounce)
        fill(16, rightUp ? 1 : 2, color, dy: bounce)
        for x in 3...14 { fill(x, 3, color, dy: bounce) }

        // Pattes : au travail, une paire sur deux se lève à chaque pas.
        let legs = [4, 6, 11, 13]
        for (index, x) in legs.enumerated() {
            let lifted = mood == .working && (index % 2 == tick % 2)
            fill(x, 4, color, dy: lifted ? -pixelHeight * 0.45 : 0)
        }
        canvas.fill(shape, with: .color(color))
    }
}

#Preview {
    VStack(spacing: 20) {
        ClaudeMascot(mood: .idle).frame(width: 90)
        ClaudeMascot(mood: .working).frame(width: 90)
        ClaudeMascot(mood: .waiting).frame(width: 90)
    }
    .padding(30)
    .background(.black)
}
