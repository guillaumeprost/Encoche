import CoreAudio

/// Lecture et écriture des propriétés CoreAudio (volume, muet, appareils), partagées par
/// le volume, les commandes de visio et le témoin du micro.
enum AudioHardware {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    enum Scope {
        case global, input, output

        var value: AudioObjectPropertyScope {
            switch self {
            case .global: kAudioObjectPropertyScopeGlobal
            case .input: kAudioDevicePropertyScopeInput
            case .output: kAudioDevicePropertyScopeOutput
            }
        }
    }

    static func address(_ selector: AudioObjectPropertySelector, _ scope: Scope = .global) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope.value, mElement: kAudioObjectPropertyElementMain)
    }

    static func has(_ selector: AudioObjectPropertySelector, _ scope: Scope = .global, on object: AudioObjectID) -> Bool {
        var address = address(selector, scope)
        return AudioObjectHasProperty(object, &address)
    }

    static func isSettable(_ selector: AudioObjectPropertySelector, _ scope: Scope = .global, on object: AudioObjectID) -> Bool {
        var address = address(selector, scope)
        var settable = DarwinBoolean(false)
        return AudioObjectHasProperty(object, &address)
            && AudioObjectIsPropertySettable(object, &address, &settable) == noErr && settable.boolValue
    }

    /// Valeur de la propriété (`UInt32`, `Float32`, identifiant d'appareil…), ou `nil` si absente.
    static func get<Value: Numeric & BitwiseCopyable>(
        _ selector: AudioObjectPropertySelector, _ scope: Scope = .global, on object: AudioObjectID
    ) -> Value? {
        var address = address(selector, scope)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: Value = 0
        var size = UInt32(MemoryLayout<Value>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    /// Écrit la propriété ; `false` si l'appareil ne la propose pas ou la refuse.
    @discardableResult
    static func set<Value: Numeric & BitwiseCopyable>(
        _ value: Value, _ selector: AudioObjectPropertySelector, _ scope: Scope = .global, on object: AudioObjectID
    ) -> Bool {
        var address = address(selector, scope)
        guard AudioObjectHasProperty(object, &address) else { return false }
        var value = value
        return AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<Value>.size), &value) == noErr
    }

    /// Sortie ou entrée par défaut du Mac.
    static func defaultDevice(_ scope: Scope) -> AudioObjectID? {
        let selector =
            scope == .input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
        let device: AudioObjectID? = get(selector, on: system)
        return device == kAudioObjectUnknown ? nil : device
    }

    /// Tous les appareils audio.
    static func devices() -> [AudioObjectID] {
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices
    }

    /// L'appareil a des canaux d'entrée (micro).
    static func hasInput(_ device: AudioObjectID) -> Bool {
        var address = address(kAudioDevicePropertyStreams, .input)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }
}
