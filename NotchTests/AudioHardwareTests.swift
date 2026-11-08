import AudioToolbox
import CoreAudio
import Testing

@testable import Encoche

/// Lecture CoreAudio sur les vrais appareils du Mac. Rien n'est modifié (ni volume, ni micro).
/// Sans appareil audio (machine de CI), les vérifications sur l'appareil sont sautées.
struct AudioHardwareTests {
    @Test func defaultDevicesAreListed() {
        let devices = AudioHardware.devices()
        for scope in [AudioHardware.Scope.output, .input] {
            guard let device = AudioHardware.defaultDevice(scope) else { continue }
            #expect(devices.contains(device))
        }
    }

    @Test func outputVolumeIsAFraction() {
        guard let device = AudioHardware.defaultDevice(.output),
            let volume: Float32 = AudioHardware.get(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, .output, on: device)
        else { return }
        #expect((0...1).contains(volume))
    }

    @Test func onlyInputDevicesHaveInputStreams() {
        guard let input = AudioHardware.defaultDevice(.input) else { return }
        #expect(AudioHardware.hasInput(input))
    }

    @Test func missingPropertiesGiveNothing() {
        let volume: Float32? = AudioHardware.get(kAudioDevicePropertyVolumeScalar, .output, on: AudioHardware.system)
        #expect(volume == nil)
        #expect(!AudioHardware.has(kAudioDevicePropertyVolumeScalar, .output, on: AudioHardware.system))
        #expect(!AudioHardware.isSettable(kAudioDevicePropertyMute, .output, on: AudioObjectID(kAudioObjectUnknown)))
        #expect(!AudioHardware.set(Float32(0.5), kAudioDevicePropertyVolumeScalar, .output, on: AudioObjectID(kAudioObjectUnknown)))
    }
}
