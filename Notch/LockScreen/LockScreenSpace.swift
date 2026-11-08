import AppKit

/// Espace d'affichage au-dessus de l'écran de verrouillage.
///
/// macOS n'a pas d'API publique pour afficher une fenêtre sur l'écran de verrouillage :
/// on passe par SkyLight (privé), comme les autres apps d'encoche. On crée un espace placé
/// au niveau des notifications de l'écran verrouillé, et on y déplace nos fenêtres.
/// Si une mise à jour de macOS change ces fonctions, `shared` vaut `nil` et rien ne s'affiche.
@MainActor
final class LockScreenSpace {
    static let shared = LockScreenSpace()

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindowsAndRemoveFromSpaces = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    /// Niveau des notifications sur l'écran verrouillé (au-dessus de l'écran de verrouillage).
    private static let notificationCenterAtScreenLock: Int32 = 400

    private let connection: Int32
    private let space: Int32
    private let addWindows: AddWindowsAndRemoveFromSpaces

    private init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW),
            let mainConnection = dlsym(handle, "SLSMainConnectionID"),
            let spaceCreate = dlsym(handle, "SLSSpaceCreate"),
            let setLevel = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
            let showSpaces = dlsym(handle, "SLSShowSpaces"),
            let addWindows = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces")
        else { return nil }

        connection = unsafeBitCast(mainConnection, to: MainConnectionID.self)()
        space = unsafeBitCast(spaceCreate, to: SpaceCreate.self)(connection, 1, 0)
        _ = unsafeBitCast(setLevel, to: SpaceSetAbsoluteLevel.self)(connection, space, Self.notificationCenterAtScreenLock)
        _ = unsafeBitCast(showSpaces, to: ShowSpaces.self)(connection, [space] as CFArray)
        self.addWindows = unsafeBitCast(addWindows, to: AddWindowsAndRemoveFromSpaces.self)
    }

    /// Place la fenêtre (déjà affichée) dans l'espace de l'écran de verrouillage.
    func add(_ window: NSWindow) {
        _ = addWindows(connection, space, [window.windowNumber] as CFArray, 7)
    }
}
