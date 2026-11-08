import AudioToolbox
import CoreAudio
import Observation

/// Volume de la sortie audio par défaut (haut-parleurs, casque, AirPods…), via CoreAudio.
///
/// On écoute les changements (touches de volume, Centre de contrôle, autre app) pour
/// afficher l'indicateur dans l'encoche, et on peut régler le volume depuis l'encoche.
@Observable
@MainActor
final class VolumeController {
    private(set) var volume: Float = 0
    private(set) var isMuted = false
    /// La sortie actuelle permet de régler le volume (pas toujours le cas, ex. écran en HDMI).
    private(set) var isAdjustable = false

    @ObservationIgnored private var device = AudioObjectID(kAudioObjectUnknown)
    @ObservationIgnored var hud: HUDCenter?
    /// Les touches de luminosité passent par le même canal que celles du volume.
    @ObservationIgnored var brightness: BrightnessController?
    /// Changement venant de notre propre réglage : pas d'indicateur par-dessus le curseur.
    @ObservationIgnored private var isSettingVolume = false

    @ObservationIgnored private var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    @ObservationIgnored private var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    @ObservationIgnored private var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    @ObservationIgnored private var listener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var deviceListener: AudioObjectPropertyListenerBlock?

    init() {
        // Les blocs sont appelés sur la file principale (paramètre `.main`).
        listener = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.readState(showHUD: true) }
        }
        let deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attachToDefaultDevice() }
        }
        self.deviceListener = deviceListener
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, .main, deviceListener
        )
        attachToDefaultDevice()
    }

    /// Icône du haut-parleur selon le niveau.
    var symbol: String {
        if isMuted || volume == 0 { return "speaker.slash.fill" }
        switch volume {
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    // MARK: - Réglage

    func setVolume(_ value: Float) {
        guard isAdjustable else { return }
        var newValue = min(max(value, 0), 1)
        isSettingVolume = true
        AudioObjectSetPropertyData(device, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &newValue)
        if isMuted, newValue > 0 { setMuted(false) }
        volume = newValue
        isSettingVolume = false
    }

    // MARK: - Touches de volume (à la place de macOS)

    /// Comme macOS : 16 crans, ou 64 avec Option + Maj.
    private static let step: Float = 1 / 16
    private static let fineStep: Float = 1 / 64

    @ObservationIgnored private let keys = VolumeKeyInterceptor()
    @ObservationIgnored var alerts: AlertCenter?
    /// Active ou non le remplacement de l'indicateur de macOS.
    func setReplacesSystemHUD(_ enabled: Bool) {
        guard enabled else {
            keys.stop()
            return
        }
        keys.onKey = { [weak self] key, fine in self?.handleKey(key, fine: fine) ?? false }
        if VolumeKeyInterceptor.isTrusted {
            keys.start()
        } else {
            askForAccessibilityOnce()
            keys.start() // réessaie seul dès que l'autorisation est accordée
        }
    }

    func requestAccessibility() {
        keys.openAccessibilitySettings()
        keys.requestAccessAndStart()
    }

    private func handleKey(_ key: VolumeKeyInterceptor.Key, fine: Bool) -> Bool {
        switch key {
        case .brightnessUp: return brightness?.handleKey(up: true, fine: fine) ?? false
        case .brightnessDown: return brightness?.handleKey(up: false, fine: fine) ?? false
        default: break
        }
        // Sortie non réglable (ex. HDMI) : on laisse macOS gérer et prévenir.
        guard isAdjustable else { return false }
        let step = fine ? Self.fineStep : Self.step
        switch key {
        case .up:
            let base = isMuted ? 0 : volume
            setVolume(((base + step) / step).rounded() * step)
        case .down:
            setVolume(max(((volume - step) / step).rounded() * step, 0))
        case .mute:
            toggleMute()
        case .brightnessUp, .brightnessDown:
            break
        }
        flashHUD()
        return true
    }

    private func askForAccessibilityOnce() {
        let key = "volumeAccessibilityOnboardingShown"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        alerts?.post(
            NotchAlert(
                icon: .symbol("speaker.wave.2.fill", .gray),
                source: "Encoche",
                title: "Remplacer l'indicateur de volume de macOS ?",
                body: "Clique pour autoriser Encoche dans « Accessibilité ».",
                action: .run { [weak self] in self?.requestAccessibility() }
            ))
    }

    func toggleMute() {
        setMuted(!isMuted)
    }

    private func setMuted(_ muted: Bool) {
        var value: UInt32 = muted ? 1 : 0
        isSettingVolume = true
        AudioObjectSetPropertyData(device, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        isMuted = muted
        isSettingVolume = false
    }

    // MARK: - Lecture

    private func attachToDefaultDevice() {
        if device != kAudioObjectUnknown, let listener {
            AudioObjectRemovePropertyListenerBlock(device, &volumeAddress, .main, listener)
            AudioObjectRemovePropertyListenerBlock(device, &muteAddress, .main, listener)
        }

        var newDevice = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, 0, nil, &size, &newDevice
        )
        device = newDevice
        guard device != kAudioObjectUnknown else {
            isAdjustable = false
            return
        }

        if let listener {
            AudioObjectAddPropertyListenerBlock(device, &volumeAddress, .main, listener)
            AudioObjectAddPropertyListenerBlock(device, &muteAddress, .main, listener)
        }
        // Changement de sortie (ex. AirPods connectés) : on lit l'état sans afficher l'indicateur.
        readState(showHUD: false)
    }

    private func readState(showHUD: Bool) {
        var settable: DarwinBoolean = false
        isAdjustable =
            AudioObjectHasProperty(device, &volumeAddress)
            && AudioObjectIsPropertySettable(device, &volumeAddress, &settable) == noErr
            && settable.boolValue

        var newVolume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &newVolume) != noErr {
            newVolume = 0
        }

        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(device, &muteAddress) {
            AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &muted)
        }

        let changed = abs(newVolume - volume) > 0.001 || (muted != 0) != isMuted
        volume = newVolume
        isMuted = muted != 0

        if showHUD, changed, !isSettingVolume { flashHUD() }
    }

    private func flashHUD() {
        hud?.show(.volume)
    }
}
