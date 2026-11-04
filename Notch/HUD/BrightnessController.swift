import CoreGraphics
import Foundation
import Observation

/// Luminosité de l'écran intégré du Mac.
///
/// macOS n'a pas d'API publique pour la régler : on passe par DisplayServices, la
/// bibliothèque système qu'utilisent aussi les touches de luminosité. Chargée à
/// l'exécution ; si elle est absente ou change, la fonction se désactive simplement
/// et macOS garde la main sur les touches.
@Observable
@MainActor
final class BrightnessController {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let step: Float = 1 / 16
    private static let fineStep: Float = 1 / 64

    private(set) var brightness: Float = 0

    @ObservationIgnored var hud: HUDCenter?
    @ObservationIgnored private var getter: GetBrightness?
    @ObservationIgnored private var setter: SetBrightness?

    init() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let get = dlsym(handle, "DisplayServicesGetBrightness"),
              let set = dlsym(handle, "DisplayServicesSetBrightness") else { return }
        getter = unsafeBitCast(get, to: GetBrightness.self)
        setter = unsafeBitCast(set, to: SetBrightness.self)
    }

    var symbol: String { brightness < 0.5 ? "sun.min.fill" : "sun.max.fill" }

    /// Écran intégré (celui que règlent les touches de luminosité du Mac).
    private var builtInDisplay: CGDirectDisplayID? {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &displays, &count)
        return displays.first { CGDisplayIsBuiltin($0) != 0 }
    }

    /// Touche de luminosité : renvoie `false` si on ne peut pas la gérer (macOS s'en charge).
    func handleKey(up: Bool, fine: Bool) -> Bool {
        guard let getter, let setter, let display = builtInDisplay else { return false }
        var current: Float = 0
        guard getter(display, &current) == 0 else { return false }

        let step = fine ? Self.fineStep : Self.step
        let target = min(max(((current + (up ? step : -step)) / step).rounded() * step, 0), 1)
        guard setter(display, target) == 0 else { return false }
        brightness = target
        hud?.show(.brightness)
        return true
    }
}
