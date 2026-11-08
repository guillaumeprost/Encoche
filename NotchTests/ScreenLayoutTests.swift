import CoreGraphics
import Testing

@testable import Encoche

/// Placement de l'encoche selon l'écran, sans vrai écran.
struct ScreenLayoutTests {
    /// MacBook Pro 14" (1512 × 982 points) et écran externe 2560 × 1440 placé à sa droite.
    private let macBook = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let external = CGRect(x: 1512, y: 0, width: 2560, height: 1440)

    @Test func physicalNotchSitsBetweenTheMenuBarAreas() {
        let size = ScreenLayout.notchSize(
            frame: macBook, visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950), safeAreaTop: 32,
            leftArea: CGRect(x: 0, y: 950, width: 663, height: 32),
            rightArea: CGRect(x: 849, y: 950, width: 663, height: 32))
        #expect(size == CGSize(width: 186, height: 32))
    }

    @Test func screensWithoutNotchGetOneAtMenuBarHeight() {
        let size = ScreenLayout.notchSize(
            frame: external, visibleFrame: CGRect(x: 1512, y: 0, width: 2560, height: 1415), safeAreaTop: 0,
            leftArea: nil, rightArea: nil)
        #expect(size == CGSize(width: ScreenLayout.simulatedNotchWidth, height: 25))
    }

    @Test func hiddenMenuBarFallsBackToADefaultHeight() {
        let size = ScreenLayout.notchSize(
            frame: external, visibleFrame: external, safeAreaTop: 0, leftArea: nil, rightArea: nil)
        #expect(size.height == ScreenLayout.fallbackMenuBarHeight)
    }

    @Test func panelIsCenteredAtTheTopOfItsScreen() {
        let frame = ScreenLayout.topCenter(CGSize(width: 880, height: 280), in: external)
        #expect(frame == CGRect(x: 1512 + 1280 - 440, y: 1440 - 280, width: 880, height: 280))
    }

    @Test func lockScreenPrefersTheMacBookScreen() {
        // Écran externe principal, MacBook ouvert à côté.
        let screens = [(name: "externe", notch: false), (name: "MacBook", notch: true)]
        #expect(ScreenLayout.lockScreen(among: screens, hasNotch: \.notch)?.name == "MacBook")
        // MacBook fermé : seul l'écran externe reste.
        #expect(ScreenLayout.lockScreen(among: [screens[0]], hasNotch: \.notch)?.name == "externe")
        #expect(ScreenLayout.lockScreen(among: [(name: String, notch: Bool)](), hasNotch: \.notch) == nil)
    }

    @Test func lockScreenWindowsAvoidTheClockAndTheLogin() {
        let frames = ScreenLayout.lockFrames(screen: macBook, notchWidth: 280, notchHeight: 32)
        #expect(frames.notch == CGRect(x: 756 - 140, y: 950, width: 280, height: 32))
        // Activités juste sous l'horloge, lecteur juste au-dessus de la photo de profil.
        #expect(frames.activities.maxY == macBook.maxY - macBook.height * ScreenLayout.lockClockFraction)
        #expect(frames.music.minY == macBook.height * ScreenLayout.lockLoginFraction)
        #expect(frames.activities.minY - frames.music.maxY >= ScreenLayout.lockSpacing)
        for frame in [frames.notch, frames.activities, frames.music] {
            #expect(frame.midX == macBook.midX)
            #expect(macBook.contains(frame))
        }
    }

    @Test func lockScreenFollowsASecondScreen() {
        let frames = ScreenLayout.lockFrames(screen: external, notchWidth: 280, notchHeight: 25)
        // Grand écran : toute la hauteur prévue pour les activités.
        #expect(frames.activities.height == ScreenLayout.lockActivitiesSize.height)
        for frame in [frames.notch, frames.activities, frames.music] {
            #expect(external.contains(frame))
        }
    }

    @Test func quartzFramesStartAtTheTopOfThePrimaryScreen() {
        #expect(ScreenLayout.quartzFrame(macBook, primaryHeight: 982) == macBook)
        // Écran plus haut à droite : il dépasse au-dessus du principal.
        #expect(
            ScreenLayout.quartzFrame(external, primaryHeight: 982)
                == CGRect(x: 1512, y: 982 - 1440, width: 2560, height: 1440))
    }

    @Test func fullScreenDetection() {
        let screens: [Int: CGRect] = [1: macBook, 2: CGRect(x: 1512, y: -458, width: 2560, height: 1440)]
        // Fenêtre plein écran sur l'écran externe, fenêtre normale sur le MacBook.
        let windows = [CGRect(x: 1512, y: -458, width: 2560, height: 1440), CGRect(x: 100, y: 100, width: 800, height: 600)]
        #expect(ScreenLayout.coveredDisplays(screens: screens, windows: windows) == [2])
        // Un point d'écart (arrondi) compte quand même.
        let almost = [CGRect(x: 0.5, y: 0.5, width: 1511, height: 981)]
        #expect(ScreenLayout.coveredDisplays(screens: screens, windows: almost) == [1])
        #expect(ScreenLayout.coveredDisplays(screens: screens, windows: []).isEmpty)
    }
}
