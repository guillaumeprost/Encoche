import Foundation
import IOKit.ps
import Observation

/// Batterie du Mac : niveau et charge. Quand on branche ou débranche le chargeur,
/// l'encoche affiche le niveau, comme sur iPhone.
@Observable
@MainActor
final class BatteryMonitor {
    private(set) var level = 0
    private(set) var isCharging = false
    private(set) var isPluggedIn = false
    private(set) var hasBattery = false

    @ObservationIgnored var hud: HUDCenter?
    @ObservationIgnored private var source: CFRunLoopSource?

    init() {
        read()
        let context = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.powerSourceChanged() }
        }, context)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    var symbol: String {
        if isCharging || isPluggedIn { return "battery.100percent.bolt" }
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private func powerSourceChanged() {
        let wasPluggedIn = isPluggedIn
        read()
        // Seulement au branchement / débranchement, pas à chaque pourcent.
        if hasBattery, isPluggedIn != wasPluggedIn {
            hud?.show(.battery, for: .milliseconds(2500))
        }
    }

    private func read() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for item in list {
            guard let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            hasBattery = true
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
            level = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
            isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            isPluggedIn = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return
        }
    }
}
