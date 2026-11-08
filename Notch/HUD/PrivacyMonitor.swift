import CoreAudio
import CoreMediaIO
import Observation

/// Caméra et micro en cours d'utilisation par n'importe quelle app (visio, enregistrement…),
/// comme les points vert et orange de l'iPhone. Lecture seule : aucune permission requise.
@Observable
@MainActor
final class PrivacyMonitor {
    private(set) var isCameraInUse = false
    private(set) var isMicrophoneInUse = false

    var isActive: Bool { isCameraInUse || isMicrophoneInUse }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var soonTask: Task<Void, Never>?

    init() {
        // Les deux API ont des écouteurs, mais leur liste d'appareils change (casque, webcam
        // branchée…) : une lecture toutes les 3 s est plus simple et reste très légère.
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Après une action sur la caméra ou le micro : l'app met un instant à les allumer ou
    /// les libérer, on relit l'état plusieurs fois sans attendre la lecture régulière (3 s).
    func refreshSoon() {
        soonTask?.cancel()
        soonTask = Task { [weak self] in
            for delay in [400, 800, 1_500] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    private func refresh() {
        let camera = Self.cameraInUse()
        let microphone = Self.microphoneInUse()
        if camera != isCameraInUse { isCameraInUse = camera }
        if microphone != isMicrophoneInUse { isMicrophoneInUse = microphone }
    }

    // MARK: - Caméra (CoreMediaIO)

    private static func cameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == 0 else {
            return false
        }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard
            CMIOObjectGetPropertyData(
                CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices
            ) == 0
        else { return false }

        var running = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )
        return devices.contains { device in
            var value: UInt32 = 0
            var read: UInt32 = 0
            return CMIOObjectGetPropertyData(device, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size), &read, &value) == 0
                && value != 0
        }
    }

    // MARK: - Micro (CoreAudio)

    private static func microphoneInUse() -> Bool {
        // Seulement les appareils d'entrée (micros).
        AudioHardware.devices().contains { device in
            AudioHardware.hasInput(device)
                && AudioHardware.flag(kAudioDevicePropertyDeviceIsRunningSomewhere, on: device) == true
        }
    }
}
