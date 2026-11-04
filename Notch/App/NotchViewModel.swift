import AppKit
import Observation

@Observable
@MainActor
final class NotchViewModel {
    var isOpen = false
    /// Taille de l'encoche physique (ou d'une encoche simulée sur un écran sans encoche).
    var notchSize = CGSize(width: 185, height: 32)
    var hasPhysicalNotch = true
    /// Garde l'encoche ouverte même si la souris sort (saisie en cours dans un champ).
    var holdOpen = false
    /// Rangée au-dessus de l'écran (app en plein écran, barre de menus masquée).
    var isRetracted = false
    /// Une notification est affichée (encoche élargie façon Dynamic Island).
    var showsAlert = false
    /// La notification affichée porte des boutons (demande de permission).
    var alertHasButtons = false
    /// Un fichier est en train d'être glissé au-dessus de l'encoche ouverte : zones de dépôt.
    var isDraggingFile = false

    static let expandedBodyWidth: CGFloat = 640
    static let expandedContentHeight: CGFloat = 136
    /// Hauteur en plus pour l'accueil, qui porte le champ Claude sous la musique et le calendrier.
    static let homeExtraHeight: CGFloat = 42
    static let alertBodyWidth: CGFloat = 380
    static let alertContentHeight: CGFloat = 60
    static let alertButtonsHeight: CGFloat = 36

    var topRadius: CGFloat { isOpen || showsAlert ? 12 : 6 }
    var bottomRadius: CGFloat { isOpen ? 26 : showsAlert ? 22 : 9 }

    /// Largeur d'une case latérale de la « live activity » repliée.
    var activitySlotWidth: CGFloat { notchSize.height + 8 }

    /// Taille totale de la forme, évasements du haut compris.
    func shapeSize(showsActivity: Bool, extraHeight: CGFloat = 0) -> CGSize {
        let bodyWidth: CGFloat
        let height: CGFloat
        if isOpen {
            bodyWidth = Self.expandedBodyWidth
            height = notchSize.height + Self.expandedContentHeight + extraHeight
        } else if showsAlert {
            bodyWidth = max(alertHasButtons ? 440 : Self.alertBodyWidth, notchSize.width + 2 * activitySlotWidth)
            height = notchSize.height + Self.alertContentHeight + (alertHasButtons ? Self.alertButtonsHeight : 0)
        } else if showsActivity {
            bodyWidth = notchSize.width + 2 * activitySlotWidth
            height = notchSize.height
        } else {
            bodyWidth = notchSize.width
            height = notchSize.height
        }
        return CGSize(width: bodyWidth + 2 * topRadius, height: height)
    }
}
