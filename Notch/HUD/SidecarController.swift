import Foundation
import Observation
import SwiftUI

/// iPad en second écran (Sidecar), activé ou coupé depuis l'encoche.
///
/// Pas d'API publique : on passe par SidecarCore (privé), comme le Centre de contrôle.
/// Si une mise à jour de macOS le change, le bouton disparaît simplement.
@Observable
@MainActor
final class SidecarController {
    struct Device: Identifiable, Equatable {
        let id: String
        let name: String
    }

    private(set) var devices: [Device] = []
    private(set) var connected: Set<String> = []
    /// Connexion ou déconnexion en cours.
    private(set) var busy = false

    @ObservationIgnored private var manager: NSObject?
    @ObservationIgnored private var objects: [String: NSObject] = [:]

    init() {
        guard dlopen("/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore", RTLD_NOW) != nil,
            let type = NSClassFromString("SidecarDisplayManager") as? NSObject.Type,
            type.responds(to: NSSelectorFromString("sharedManager"))
        else { return }
        manager = type.perform(NSSelectorFromString("sharedManager"))?.takeUnretainedValue() as? NSObject
        refresh()
    }

    var isAvailable: Bool { manager != nil && !devices.isEmpty }

    func isConnected(_ device: Device) -> Bool { connected.contains(device.id) }

    /// Relit les iPad disponibles et ceux qui sont connectés.
    func refresh() {
        guard let manager else { return }
        let all = manager.value(forKey: "devices") as? [NSObject] ?? []
        let active = manager.value(forKey: "connectedDevices") as? [NSObject] ?? []
        var map: [String: NSObject] = [:]
        devices = all.compactMap { object in
            guard let name = object.value(forKey: "name") as? String else { return nil }
            let id = Self.identifier(of: object) ?? name
            map[id] = object
            return Device(id: id, name: name)
        }
        objects = map
        connected = Set(active.compactMap { Self.identifier(of: $0) ?? ($0.value(forKey: "name") as? String) })
    }

    /// Connecte l'iPad, ou le déconnecte s'il l'est déjà.
    func toggle(_ device: Device) {
        guard let manager, let object = objects[device.id], !busy else { return }
        busy = true
        let selector = NSSelectorFromString(isConnected(device) ? "disconnectFromDevice:completion:" : "connectToDevice:completion:")
        guard manager.responds(to: selector) else {
            busy = false
            return
        }

        typealias Method = @convention(c) (NSObject, Selector, NSObject, @escaping @convention(block) (NSError?) -> Void) -> Void
        let call = unsafeBitCast(manager.method(for: selector), to: Method.self)
        call(manager, selector, object) { [weak self] error in
            if let error { NSLog("[Encoche] Sidecar failed: \(error.localizedDescription)") }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.busy = false
                    self?.refresh()
                }
            }
        }
    }

    private static func identifier(of device: NSObject) -> String? {
        guard device.responds(to: NSSelectorFromString("identifier")) else { return nil }
        return (device.value(forKey: "identifier") as? NSUUID)?.uuidString ?? device.value(forKey: "identifier") as? String
    }
}

/// Bouton iPad en haut à gauche de l'encoche ouverte : active ou coupe Sidecar.
struct SidecarButton: View {
    @Environment(SidecarController.self) private var sidecar
    @State private var hovering = false

    var body: some View {
        Group {
            if sidecar.isAvailable {
                if sidecar.devices.count == 1, let device = sidecar.devices.first {
                    Button {
                        sidecar.toggle(device)
                    } label: {
                        label
                    }
                    .buttonStyle(.plain)
                    .help(sidecar.isConnected(device) ? "Arrêter Sidecar sur \(device.name)" : "Utiliser \(device.name) comme écran")
                } else {
                    Menu {
                        ForEach(sidecar.devices) { device in
                            Button(
                                sidecar.isConnected(device) ? "Arrêter Sidecar sur \(device.name)" : "Utiliser \(device.name) comme écran"
                            ) {
                                sidecar.toggle(device)
                            }
                        }
                    } label: {
                        label
                    }
                    .plainMenu()
                }
            }
        }
        .onAppear { sidecar.refresh() }
    }

    private var isOn: Bool { !sidecar.connected.isEmpty }

    private var label: some View {
        ZStack {
            if sidecar.busy {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: isOn ? "ipad.landscape.badge.play" : "ipad.landscape")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isOn ? Color.blue : Color.primary)
            }
        }
        .frame(width: 26, height: 22)
        .background(Capsule().fill(isOn ? Color.blue.opacity(0.18) : .primary.opacity(hovering ? 0.12 : 0)))
        .opacity(hovering || isOn ? 1 : 0.6)
        .contentShape(Capsule())
        .onHover { hovering = $0 }
    }
}
