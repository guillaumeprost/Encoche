import SwiftUI

/// Indicateur de volume façon iPhone : icône du haut-parleur, barre et pourcentage.
struct VolumeHUDView: View {
    @Environment(VolumeController.self) private var volume

    var body: some View {
        LevelHUD(
            symbol: volume.symbol,
            level: volume.isMuted ? 0 : Double(volume.volume),
            label: volume.isMuted ? "—" : "\(Int((volume.volume * 100).rounded()))"
        )
    }
}
