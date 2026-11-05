import Foundation
import IOBluetooth
import Observation

/// Connexion et déconnexion des appareils Bluetooth (AirPods, casque, clavier…),
/// annoncées sous l'encoche avec la batterie de l'appareil quand macOS la connaît.
@Observable
@MainActor
final class BluetoothMonitor: NSObject {
    struct Event: Equatable {
        let address: String
        let name: String
        let symbol: String
        let isConnected: Bool
        var battery: Int?
    }

    private(set) var lastEvent: Event?

    @ObservationIgnored var hud: HUDCenter?
    @ObservationIgnored var isEnabled: () -> Bool = { true }
    @ObservationIgnored private var connectNotification: IOBluetoothUserNotification?
    @ObservationIgnored private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    /// À l'abonnement, macOS annonce les appareils déjà connectés : on les ignore.
    @ObservationIgnored private let startDate = Date()

    func start() {
        guard connectNotification == nil else { return }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        disconnectNotifications[address]?.unregister()
        disconnectNotifications[address] = device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:))
        )
        guard Date().timeIntervalSince(startDate) > 3 else { return }
        announce(device, connected: true)
        Task { await self.loadBattery(address: address) }
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        if let address = device.addressString { disconnectNotifications[address] = nil }
        announce(device, connected: false)
    }

    private func announce(_ device: IOBluetoothDevice, connected: Bool) {
        guard isEnabled() else { return }
        let name = device.name ?? "Appareil Bluetooth"
        lastEvent = Event(
            address: device.addressString ?? name,
            name: name,
            symbol: Self.symbol(for: device),
            isConnected: connected,
            battery: nil
        )
        hud?.show(.device, for: .seconds(connected ? 3.5 : 2.5))
    }

    /// La batterie des AirPods n'a pas d'API publique : on la lit dans le rapport système,
    /// qui la donne quelques secondes après la connexion.
    private func loadBattery(address: String) async {
        for delay in [1.5, 3.0] {
            try? await Task.sleep(for: .seconds(delay))
            guard lastEvent?.address == address, lastEvent?.isConnected == true else { return }
            if let level = await Self.batteryLevel(address: address) {
                lastEvent?.battery = level
                hud?.show(.device, for: .seconds(3))
                return
            }
        }
    }

    private nonisolated static func batteryLevel(address: String) async -> Int? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
                process.arguments = ["SPBluetoothDataType", "-json"]
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                guard (try? process.run()) != nil else { return continuation.resume(returning: nil) }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: parseBattery(data, address: address))
            }
        }
    }

    /// `SPBluetoothDataType[0].device_connected` : `[{ "Nom": { "device_address": …, "device_batteryLevelLeft": "80%" … } }]`.
    private nonisolated static func parseBattery(_ data: Data, address: String) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
        let wanted = normalized(address)
        for controller in controllers {
            for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                for case let info as [String: Any] in entry.values {
                    guard normalized(info["device_address"] as? String ?? "") == wanted else { continue }
                    // Écouteurs : le plus faible des deux ; sinon la batterie principale.
                    let buds = ["device_batteryLevelLeft", "device_batteryLevelRight"].compactMap { percent(info[$0]) }
                    if let lowest = buds.min() { return lowest }
                    return percent(info["device_batteryLevelMain"]) ?? percent(info["device_batteryLevel"])
                }
            }
        }
        return nil
    }

    private nonisolated static func percent(_ value: Any?) -> Int? {
        (value as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) }
    }

    private nonisolated static func normalized(_ address: String) -> String {
        address.uppercased().replacingOccurrences(of: "-", with: ":")
    }

    private static func symbol(for device: IOBluetoothDevice) -> String {
        let name = (device.name ?? "").lowercased()
        if name.contains("airpods max") { return "airpods.max" }
        if name.contains("airpods pro") { return "airpods.pro" }
        if name.contains("airpods") { return "airpods" }
        if name.contains("beats") { return "beats.headphones" }
        if name.contains("keyboard") || name.contains("clavier") { return "keyboard" }
        if name.contains("mouse") || name.contains("souris") { return "magicmouse" }
        if name.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if name.contains("iphone") { return "iphone" }
        if name.contains("controller") || name.contains("manette") { return "gamecontroller.fill" }
        // Classe Bluetooth « audio » (casques, enceintes).
        if device.deviceClassMajor == UInt32(kBluetoothDeviceClassMajorAudio) { return "headphones" }
        if device.deviceClassMajor == UInt32(kBluetoothDeviceClassMajorPeripheral) { return "keyboard" }
        return "dot.radiowaves.left.and.right"
    }
}
