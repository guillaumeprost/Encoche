import CoreGraphics

/// Calculs de placement selon l'écran (encoche, écran verrouillé, plein écran).
/// Sans AppKit : ils se testent avec de simples rectangles.
enum ScreenLayout {
    /// Encoche simulée sur un écran qui n'en a pas.
    static let simulatedNotchWidth: CGFloat = 190
    static let fallbackMenuBarHeight: CGFloat = 24

    /// Taille de l'encoche physique (entre les deux zones de la barre de menus qui l'entourent),
    /// ou d'une encoche simulée à la hauteur de la barre de menus.
    static func notchSize(
        frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat, leftArea: CGRect?, rightArea: CGRect?
    ) -> CGSize {
        if safeAreaTop > 0, let leftArea, let rightArea {
            return CGSize(width: frame.width - leftArea.width - rightArea.width, height: safeAreaTop)
        }
        let menuBarHeight = frame.maxY - visibleFrame.maxY
        return CGSize(width: simulatedNotchWidth, height: menuBarHeight > 0 ? menuBarHeight : fallbackMenuBarHeight)
    }

    /// Rectangle de cette taille, centré en haut de l'écran (collé au bord).
    static func topCenter(_ size: CGSize, in screen: CGRect) -> CGRect {
        centered(size, in: screen, y: screen.maxY - size.height)
    }

    /// Rectangle de cette taille, centré horizontalement sur l'écran, à cette hauteur.
    private static func centered(_ size: CGSize, in screen: CGRect, y: CGFloat) -> CGRect {
        CGRect(x: screen.midX - size.width / 2, y: y, width: size.width, height: size.height)
    }

    /// Écran de l'écran verrouillé : celui du Mac quand il est ouvert (sa vraie encoche),
    /// sinon l'écran principal (le premier de la liste).
    static func lockScreen<Screen>(among screens: [Screen], hasNotch: (Screen) -> Bool) -> Screen? {
        screens.first(where: hasNotch) ?? screens.first
    }

    /// Placement des fenêtres de l'écran verrouillé.
    struct LockFrames: Equatable {
        let notch: CGRect
        /// Activités sous l'horloge.
        let activities: CGRect
        /// Lecteur juste au-dessus de la photo de profil.
        let music: CGRect
    }

    static let lockActivitiesSize = CGSize(width: 420, height: 380)
    static let lockMusicSize = CGSize(width: 420, height: 124)
    /// Part du haut de l'écran prise par la date et l'horloge de l'écran verrouillé.
    static let lockClockFraction: CGFloat = 0.31
    /// Part du bas de l'écran prise par la photo de profil, le nom et le mot de passe.
    static let lockLoginFraction: CGFloat = 0.21

    /// Espace gardé entre les activités et le lecteur.
    static let lockSpacing: CGFloat = 12

    static func lockFrames(screen: CGRect, notchWidth: CGFloat, notchHeight: CGFloat) -> LockFrames {
        let music = centered(lockMusicSize, in: screen, y: screen.minY + screen.height * lockLoginFraction)
        // Sous l'horloge, sans descendre sur le lecteur (petits écrans).
        let clockBottom = screen.maxY - screen.height * lockClockFraction
        let height = max(0, min(lockActivitiesSize.height, clockBottom - music.maxY - lockSpacing))
        return LockFrames(
            notch: topCenter(CGSize(width: notchWidth, height: notchHeight), in: screen),
            activities: centered(CGSize(width: lockActivitiesSize.width, height: height), in: screen, y: clockBottom - height),
            music: music
        )
    }

    /// Cadre d'un écran en coordonnées Quartz (origine en haut à gauche de l'écran principal),
    /// celles qu'utilise CGWindowList.
    static func quartzFrame(_ frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    /// Écrans entièrement recouverts par une fenêtre (app en plein écran), en coordonnées Quartz.
    static func coveredDisplays<ID: Hashable>(screens: [ID: CGRect], windows: [CGRect]) -> Set<ID> {
        Set(
            screens.compactMap { id, frame in
                windows.contains { $0.insetBy(dx: -1, dy: -1).contains(frame) } ? id : nil
            })
    }
}
