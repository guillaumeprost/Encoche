import AppKit
import Observation

@Observable
@MainActor
final class NotchViewModel {
    var isOpen = false
    /// Taille de l'encoche physique (ou d'une encoche simulée sur un écran sans encoche).
    var notchSize = CGSize(width: 185, height: 32)
    var hasPhysicalNotch = true
    /// Écran principal de macOS (celui qui porte la barre de menus).
    var isPrimaryScreen = true
    /// Garde l'encoche ouverte même si la souris sort (saisie en cours dans un champ).
    var holdOpen = false
    /// Rangée au-dessus de l'écran (app en plein écran, barre de menus masquée).
    var isRetracted = false
    /// Une notification est affichée (encoche élargie façon Dynamic Island).
    var showsAlert = false
    /// La notification affichée porte des boutons (demande de permission).
    var alertHasButtons = false
    /// Notification survolée dont le texte est long : elle se déplie pour l'afficher en entier.
    var alertExpanded = false
    /// Un indicateur (volume, luminosité, batterie) est affiché sous l'encoche repliée.
    var showsHUD = false

    static let expandedBodyWidth: CGFloat = 640
    /// Largeur ouverte en plus de l'encoche physique : 8 onglets, minuteur et Concentration à
    /// gauche, mini-lecteur et actions à droite.
    static let sideSpaceAroundNotch: CGFloat = 520
    static let expandedContentHeight: CGFloat = 136
    /// Hauteur en plus pour l'accueil, qui porte le champ Claude sous la musique et le calendrier.
    static let homeExtraHeight: CGFloat = 42
    static let calendarExtraHeight: CGFloat = 96
    static let claudeExtraHeight: CGFloat = 110
    /// Largeur en plus pour l'accueil, qui porte une colonne de rappels.
    static let homeExtraWidth: CGFloat = 150

    /// Largeur ajoutée à l'encoche ouverte selon l'onglet.
    private static func extraWidth(for tab: NotchTab) -> CGFloat {
        tab == .home ? homeExtraWidth : 0
    }

    /// Hauteur ajoutée à l'encoche ouverte selon l'onglet.
    private static func extraHeight(for tab: NotchTab) -> CGFloat {
        switch tab {
        case .home: return homeExtraHeight
        case .calendar, .music, .reminders: return calendarExtraHeight
        case .claude: return claudeExtraHeight
        default: return 0
        }
    }
    static let alertBodyWidth: CGFloat = 380
    static let alertContentHeight: CGFloat = 66
    static let alertButtonsHeight: CGFloat = 36
    static let alertExpandedExtraHeight: CGFloat = 46
    static let hudHeight: CGFloat = 26

    var topRadius: CGFloat { isOpen || showsAlert ? 12 : 6 }
    var bottomRadius: CGFloat { isOpen ? 26 : showsAlert ? 22 : showsHUD ? 16 : 9 }

    /// Largeur d'une case latérale de la « live activity » repliée.
    var activitySlotWidth: CGFloat { notchSize.height + 8 }
    /// Une activité en direct agrandit un peu l'encoche vers le bas, pour qu'on la remarque.
    static let activityExtraHeight: CGFloat = 7
    var activityHeight: CGFloat { notchSize.height + Self.activityExtraHeight }

    /// Taille totale de la forme, évasements du haut compris.
    func shapeSize(showsActivity: Bool, tab: NotchTab) -> CGSize {
        let extraWidth = Self.extraWidth(for: tab)
        let extraHeight = Self.extraHeight(for: tab)
        let bodyWidth: CGFloat
        let height: CGFloat
        if isOpen {
            // Avec une encoche physique, les onglets se répartissent de chaque côté de la caméra :
            // un peu plus de largeur pour que les boutons de gauche et de droite tiennent à côté.
            bodyWidth = hasPhysicalNotch
                ? max(Self.expandedBodyWidth + extraWidth, notchSize.width + Self.sideSpaceAroundNotch)
                : Self.expandedBodyWidth + extraWidth
            height = notchSize.height + Self.expandedContentHeight + extraHeight
        } else if showsAlert {
            bodyWidth = max(alertHasButtons ? 440 : Self.alertBodyWidth, notchSize.width + 2 * activitySlotWidth)
            height = notchSize.height + Self.alertContentHeight + (alertHasButtons ? Self.alertButtonsHeight : 0)
                + (alertExpanded ? Self.alertExpandedExtraHeight : 0)
        } else if showsHUD {
            bodyWidth = notchSize.width + 2 * activitySlotWidth
            height = notchSize.height + Self.hudHeight
        } else if showsActivity {
            bodyWidth = notchSize.width + 2 * activitySlotWidth
            height = activityHeight
        } else {
            bodyWidth = notchSize.width
            height = notchSize.height
        }
        return CGSize(width: bodyWidth + 2 * topRadius, height: height)
    }
}
