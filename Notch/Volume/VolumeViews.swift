import SwiftUI

/// Indicateur de volume façon iPhone : sous l'encoche repliée, l'icône du haut-parleur,
/// une barre et le pourcentage.
struct VolumeHUDView: View {
    @Environment(VolumeController.self) private var volume

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: volume.symbol)
                .font(.system(size: 11, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 18)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.2))
                    Capsule().fill(.primary)
                        .frame(width: geo.size.width * CGFloat(volume.isMuted ? 0 : volume.volume))
                }
            }
            .frame(height: 5)
            Text(volume.isMuted ? "—" : "\(Int((volume.volume * 100).rounded()))")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .frame(width: 24, alignment: .trailing)
        }
        .foregroundStyle(.primary)
        .animation(.snappy(duration: 0.15), value: volume.volume)
        .animation(.snappy(duration: 0.15), value: volume.isMuted)
    }
}
