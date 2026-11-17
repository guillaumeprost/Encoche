import Foundation

/// Quand la pince doit sortir : délai de grâce, absence tolérée, répit après avoir été chassée,
/// colère. Sans écran ni minuterie (le gardien lui dit ce qui est au premier plan), pour être testé.
struct FocusGuardTracker {
    enum Decision: Equatable {
        case wait
        case intercept
    }

    /// Temps passé sur un site ou une app interdits, sans en sortir, avant que la pince arrive.
    var gracePeriod: TimeInterval
    /// Absence tolérée (lecture ratée, coup d'œil ailleurs) avant de remettre le délai à zéro.
    let leaveTolerance: TimeInterval

    /// Depuis quand tu es sur un site interdit (pour les yeux de l'encoche), `nil` sinon.
    private(set) var watchingSince: Date?
    /// Colère sur le site en cours : combien de fois tu as chassé la pince.
    private(set) var anger = 0

    /// Site ou app interdits au premier plan, et depuis quand (le délai repart de zéro dès qu'on
    /// en sort).
    private var pending: (key: String, since: Date, lastSeen: Date)?
    private var snoozedUntil: [String: Date] = [:]
    private var angerByKey: [String: Int] = [:]

    init(gracePeriod: TimeInterval, leaveTolerance: TimeInterval) {
        self.gracePeriod = gracePeriod
        self.leaveTolerance = leaveTolerance
    }

    /// Il reste quelque chose à oublier (délai en cours, colère).
    var hasState: Bool { pending != nil || !angerByKey.isEmpty || !snoozedUntil.isEmpty }

    /// Colère contre ce site ou cette app.
    func anger(for key: String) -> Int { angerByKey[key] ?? 0 }

    /// Ce qui est au premier plan à `now` : la clé du site ou de l'app interdits, `nil` sinon.
    mutating func observe(_ key: String?, at now: Date) -> Decision {
        guard let key else {
            // Une lecture ratée (page qui charge, vidéo en plein écran…) ne remet pas le
            // compteur à zéro : seulement si on a vraiment quitté le site quelques secondes.
            if let pending, now.timeIntervalSince(pending.lastSeen) > leaveTolerance {
                reset()
            } else if pending == nil, snoozedUntil.isEmpty {
                watchingSince = nil
                anger = 0
            }
            return .wait
        }
        // Un autre site : le répit et la colère de l'ancien sont oubliés.
        snoozedUntil = snoozedUntil.filter { $0.key == key }
        angerByKey = angerByKey.filter { $0.key == key }
        anger = anger(for: key)
        if let until = snoozedUntil[key] {
            guard until <= now else { return .wait }
            // Chassée, elle revient d'elle-même à la fin du répit, sans nouveau délai.
            snoozedUntil[key] = nil
            pending = nil
            return .intercept
        }
        guard let pending, pending.key == key else {
            pending = (key, now, now)
            watchingSince = now
            return .wait
        }
        self.pending?.lastSeen = now
        watchingSince = pending.since
        guard now.timeIntervalSince(pending.since) >= gracePeriod else { return .wait }
        self.pending = nil
        watchingSince = nil
        return .intercept
    }

    /// Une fois chassée, la pince revient au bout de ce temps si tu es toujours sur le site :
    /// de plus en plus vite à chaque fois (2 min, 1 min, puis 30 s).
    static func snoozeDuration(anger: Int) -> TimeInterval {
        [2 * 60, 60, 30][min(max(anger - 1, 0), 2)]
    }

    /// Chassée : elle revient de plus en plus vite, et de plus en plus fâchée.
    mutating func chased(_ key: String, at now: Date) {
        let anger = anger(for: key) + 1
        angerByKey[key] = anger
        self.anger = anger
        snoozedUntil[key] = now.addingTimeInterval(Self.snoozeDuration(anger: anger))
    }

    /// Onglet attrapé : sa colère retombe.
    mutating func grabbed(_ key: String) {
        angerByKey[key] = nil
        anger = 0
    }

    /// Plus de surveillance (désactivé, fin du Pomodoro) : tout est oublié.
    mutating func reset() {
        pending = nil
        snoozedUntil.removeAll()
        angerByKey.removeAll()
        watchingSince = nil
        anger = 0
    }
}
