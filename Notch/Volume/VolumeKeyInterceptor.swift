import AppKit
import ApplicationServices

/// Intercepte les touches de volume (et Muet) du clavier pour remplacer l'indicateur de
/// volume de macOS par celui de l'encoche : la touche n'atteint plus le système (pas
/// d'indicateur natif), et c'est nous qui réglons le volume.
///
/// Nécessite l'autorisation « Accessibilité ». Sans elle, rien n'est intercepté et
/// macOS garde son fonctionnement habituel.
@MainActor
final class VolumeKeyInterceptor {
    enum Key { case up, down, mute, brightnessUp, brightnessDown }

    /// Renvoie `true` si la touche a été traitée (elle est alors retirée du flux).
    var onKey: ((Key, _ fineStep: Bool) -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retryTimer: Timer?
    /// Touches dont l'appui a été absorbé : on absorbe aussi leur relâchement, et seulement elles.
    private var swallowedKeys: Set<Int> = []

    var isActive: Bool { tap != nil }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Demande l'autorisation Accessibilité (fenêtre système), puis démarre dès qu'elle est accordée.
    func requestAccessAndStart() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        start()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Démarre l'interception, ou réessaie toutes les 2 s tant que l'autorisation manque.
    func start() {
        guard tap == nil else { return }
        guard Self.isTrusted, installTap() else {
            if retryTimer == nil {
                retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.start() }
                }
            }
            return
        }
        retryTimer?.invalidate()
        retryTimer = nil
    }

    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private func installTap() -> Bool {
        // Touches spéciales (volume, luminosité…) : événements « système » de type 14 (NX_SYSDEFINED).
        let mask = CGEventMask(1 << 14)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let interceptor = Unmanaged<VolumeKeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()
                return MainActor.assumeIsolated { interceptor.handle(type: type, event: event) }
            },
            userInfo: refcon
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS coupe un tap trop lent ou après certaines saisies sécurisées : on le relance.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined, nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }

        let data = nsEvent.data1
        let keyCode = (data & 0xFFFF_0000) >> 16
        let keyState = (data & 0xFF00) >> 8
        let isDown = keyState == 0x0A

        let key: Key
        switch keyCode {
        case 0: key = .up       // NX_KEYTYPE_SOUND_UP
        case 1: key = .down     // NX_KEYTYPE_SOUND_DOWN
        case 7: key = .mute     // NX_KEYTYPE_MUTE
        case 2: key = .brightnessUp    // NX_KEYTYPE_BRIGHTNESS_UP
        case 3: key = .brightnessDown  // NX_KEYTYPE_BRIGHTNESS_DOWN
        default: return Unmanaged.passUnretained(event)
        }

        // Option + Maj : pas fin, comme sur macOS.
        let fine = nsEvent.modifierFlags.contains([.option, .shift])
        if isDown {
            guard onKey?(key, fine) == true else {
                swallowedKeys.remove(keyCode)
                return Unmanaged.passUnretained(event)
            }
            swallowedKeys.insert(keyCode)
            return nil
        }
        // Relâchement : absorbé seulement si l'appui l'a été, pour que macOS reçoive toujours des paires complètes.
        return swallowedKeys.remove(keyCode) != nil ? nil : Unmanaged.passUnretained(event)
    }
}
