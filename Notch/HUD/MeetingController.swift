import AppKit
import CoreAudio
import Observation
import SwiftUI

/// Commandes de visio depuis l'encoche : micro (pour toutes les apps), caméra et quitter
/// l'appel (Meet dans le navigateur, Zoom, Teams).
@Observable
@MainActor
final class MeetingController {
    /// App de visio en cours, reconnue quand la caméra ou le micro est utilisé.
    enum App: Equatable {
        case meet(browser: String)
        case zoom
        case teams

        var name: String {
            switch self {
            case .meet: "Meet"
            case .zoom: "Zoom"
            case .teams: "Teams"
            }
        }
    }

    private(set) var isMuted = false
    private(set) var app: App?

    @ObservationIgnored var privacy: PrivacyMonitor?
    /// Volume d'entrée à rétablir quand l'appareil ne sait pas se couper (pas de « mute »).
    @ObservationIgnored private var savedVolume: Float32?

    static let zoomID = "us.zoom.xos"
    static let teamsIDs = ["com.microsoft.teams2", "com.microsoft.teams"]
    static let browsers = [
        "com.apple.Safari", "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser",
    ]

    /// Un appel semble en cours : caméra ou micro utilisé, ou micro coupé par Encoche.
    var isInCall: Bool { (privacy?.isActive ?? false) || isMuted }

    init() {
        isMuted = Self.inputMuted() ?? false
    }

    // MARK: - Micro

    /// Coupe ou réactive le micro par défaut du Mac (toutes les apps l'entendent).
    func toggleMute() {
        let target = !isMuted
        guard let device = Self.defaultInputDevice() else { return }
        if Self.setMute(target, on: device) {
            isMuted = target
            return
        }
        // Pas de « mute » sur cet appareil : on passe par le volume d'entrée.
        if target {
            savedVolume = Self.inputVolume(of: device) ?? 1
            if Self.setInputVolume(0, on: device) { isMuted = true }
        } else if Self.setInputVolume(savedVolume ?? 1, on: device) {
            isMuted = false
            savedVolume = nil
        }
    }

    // MARK: - Caméra et fin d'appel

    /// Retrouve l'app de visio en cours (à l'ouverture de l'encoche pendant un appel).
    func refresh() {
        guard isInCall else {
            app = nil
            return
        }
        Task {
            let found = await Self.detectApp()
            if found != app { app = found }
        }
    }

    func toggleCamera() {
        guard let app else { return }
        switch app {
        case .meet(let browser):
            Task.detached { _ = Self.pressMeetButton(in: browser, labels: Self.meetCameraLabels) }
        case .zoom:
            press(key: 9, flags: [.maskCommand, .maskShift], bundleIDs: [Self.zoomID]) // ⇧⌘V
        case .teams:
            press(key: 31, flags: [.maskCommand, .maskShift], bundleIDs: Self.teamsIDs) // ⇧⌘O
        }
    }

    func leave() {
        guard let app else { return }
        switch app {
        case .meet(let browser):
            Task.detached { _ = Self.pressMeetButton(in: browser, labels: Self.meetLeaveLabels) }
        case .zoom:
            press(key: 13, flags: .maskCommand, bundleIDs: [Self.zoomID]) // ⌘W (Zoom demande confirmation)
        case .teams:
            press(key: 4, flags: [.maskCommand, .maskShift], bundleIDs: Self.teamsIDs) // ⇧⌘H
        }
        self.app = nil
    }

    // MARK: - Reconnaissance de l'app

    private static func detectApp() async -> App? {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        if running.contains(zoomID) { return .zoom }
        if teamsIDs.contains(where: running.contains) { return .teams }
        for browser in browsers where running.contains(browser) {
            if await hasMeetTab(in: browser) { return .meet(browser: browser) }
        }
        return nil
    }

    /// Un onglet Google Meet est ouvert dans ce navigateur.
    private static func hasMeetTab(in browser: String) async -> Bool {
        let script = """
            tell application id "\(browser)"
                repeat with w in windows
                    repeat with t in tabs of w
                        if URL of t contains "meet.google.com/" then return "yes"
                    end repeat
                end repeat
            end tell
            return "no"
            """
        return await AppleScriptRunner.run(script, cached: true)?.stringValue == "yes"
    }

    /// Libellés des boutons de Meet (français, anglais).
    nonisolated static let meetCameraLabels = ["Désactiver la caméra", "Activer la caméra", "Turn off camera", "Turn on camera"]
    nonisolated static let meetLeaveLabels = ["Quitter l'appel", "Leave call"]

    /// Clique sur un bouton de la page Meet (par l'Accessibilité, sans changer d'onglet).
    nonisolated static func pressMeetButton(in browser: String, labels: [String]) -> Bool {
        guard AXIsProcessTrusted(),
            let pid = NSRunningApplication.runningApplications(withBundleIdentifier: browser).first?.processIdentifier
        else { return false }
        let app = AX.app(pid, manual: true)
        for window in AX.elements(app, kAXWindowsAttribute) {
            for area in AX.collect(in: window, where: { AX.role($0) == "AXWebArea" }) {
                if let button = AX.first(
                    in: area, maxDepth: 40,
                    where: { element in
                        AX.role(element) == "AXButton" && matchesMeetButton(AX.label(of: element), labels: labels)
                    })
                {
                    return AX.press(button)
                }
            }
        }
        return false
    }

    /// Le libellé d'un bouton Meet commence par l'un des libellés (« Désactiver la caméra (⌘ + E) »).
    nonisolated static func matchesMeetButton(_ label: String, labels: [String]) -> Bool {
        let normalized = label.replacingOccurrences(of: "’", with: "'")
        return labels.contains { normalized.hasPrefix($0) }
    }

    private func press(key: CGKeyCode, flags: CGEventFlags, bundleIDs: [String]) {
        guard let app = bundleIDs.lazy.compactMap({ NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }).first
        else { return }
        AX.press(key: key, flags: flags, to: app.processIdentifier)
    }

    // MARK: - CoreAudio

    private static func defaultInputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
            device != 0
        else { return nil }
        return device
    }

    private static func inputAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
    }

    private static func inputMuted() -> Bool? {
        guard let device = defaultInputDevice() else { return nil }
        var address = inputAddress(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    private static func setMute(_ muted: Bool, on device: AudioDeviceID) -> Bool {
        var address = inputAddress(kAudioDevicePropertyMute)
        var settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(device, &address),
            AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue
        else { return false }
        var value = UInt32(muted ? 1 : 0)
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    private static func inputVolume(of device: AudioDeviceID) -> Float32? {
        var address = inputAddress(kAudioDevicePropertyVolumeScalar)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func setInputVolume(_ volume: Float32, on device: AudioDeviceID) -> Bool {
        var address = inputAddress(kAudioDevicePropertyVolumeScalar)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var value = volume
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }
}

/// Commandes d'appel en haut à gauche de l'encoche ouverte : micro, caméra, quitter.
struct MeetingControls: View {
    @Environment(MeetingController.self) private var meeting

    var body: some View {
        if meeting.isInCall {
            HStack(spacing: 4) {
                MeetingButton(
                    symbol: meeting.isMuted ? "mic.slash.fill" : "mic.fill",
                    tint: meeting.isMuted ? .red : .primary,
                    filled: meeting.isMuted,
                    help: meeting.isMuted ? "Réactiver le micro" : "Couper le micro"
                ) { meeting.toggleMute() }
                if let app = meeting.app {
                    MeetingButton(symbol: "video.fill", tint: .primary, filled: false, help: "Caméra (\(app.name))") {
                        meeting.toggleCamera()
                    }
                    MeetingButton(symbol: "phone.down.fill", tint: .red, filled: true, help: "Quitter l'appel (\(app.name))") {
                        meeting.leave()
                    }
                }
            }
            .onAppear { meeting.refresh() }
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }
}

private struct MeetingButton: View {
    let symbol: String
    let tint: Color
    let filled: Bool
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(filled ? Color.white : tint)
                .frame(width: 26, height: 22)
                .background(Capsule().fill(filled ? tint.opacity(hovering ? 1 : 0.85) : .primary.opacity(hovering ? 0.14 : 0.06)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
