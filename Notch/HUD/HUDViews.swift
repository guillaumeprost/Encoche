import SwiftUI

/// Contenu de l'indicateur affiché sous l'encoche repliée.
struct HUDView: View {
    let kind: HUDCenter.Kind

    var body: some View {
        switch kind {
        case .volume: VolumeHUDView()
        case .brightness: BrightnessHUDView()
        case .battery: BatteryHUDView()
        case .device: DeviceHUDView()
        }
    }
}

/// Barre de niveau commune aux indicateurs : icône, barre, valeur.
struct LevelHUD: View {
    let symbol: String
    let level: Double
    let label: String
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 18)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.2))
                    Capsule().fill(tint)
                        .frame(width: geo.size.width * min(max(level, 0), 1))
                }
            }
            .frame(height: 5)
            Text(label)
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .frame(minWidth: 24, alignment: .trailing)
        }
        .foregroundStyle(.primary)
        .animation(.snappy(duration: 0.15), value: level)
    }
}

/// Branchement / débranchement du chargeur.
struct BatteryHUDView: View {
    @Environment(BatteryMonitor.self) private var battery

    var body: some View {
        LevelHUD(
            symbol: battery.symbol,
            level: Double(battery.level) / 100,
            label: "\(battery.level) %",
            tint: battery.isPluggedIn ? .green : (battery.level <= 20 ? .red : .primary)
        )
        .symbolRenderingMode(.hierarchical)
    }
}

/// Luminosité de l'écran intégré.
struct BrightnessHUDView: View {
    @Environment(BrightnessController.self) private var brightness

    var body: some View {
        LevelHUD(
            symbol: brightness.symbol,
            level: Double(brightness.brightness),
            label: "\(Int((brightness.brightness * 100).rounded()))"
        )
    }
}

/// Caméra ou micro utilisés : icône à gauche de l'encoche, point lumineux à droite.
struct CollapsedPrivacyView: View {
    @Environment(PrivacyMonitor.self) private var privacy
    let slotWidth: CGFloat

    private var color: Color { privacy.isCameraInUse ? .green : .orange }

    var body: some View {
        CollapsedActivityLayout(slotWidth: slotWidth) {
            Image(systemName: privacy.isCameraInUse ? "video.fill" : "mic.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
        } trailing: {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.8), radius: 4)
        }
        .help(privacy.isCameraInUse ? "Caméra en cours d'utilisation" : "Micro en cours d'utilisation")
    }
}
