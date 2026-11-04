import Observation

/// Indicateurs façon iPhone affichés sous l'encoche repliée (volume, luminosité, batterie).
/// Un seul à la fois : le dernier arrivé remplace le précédent.
@Observable
@MainActor
final class HUDCenter {
    enum Kind: Equatable {
        case volume
        case brightness
        case battery
    }

    private(set) var current: Kind?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    func show(_ kind: Kind, for duration: Duration = .milliseconds(1600)) {
        current = kind
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }
}
