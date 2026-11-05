import AppKit
import Observation

/// Téléchargements en cours dans le dossier Téléchargements.
///
/// Safari, Chrome et la plupart des navigateurs publient l'avancement de leurs
/// téléchargements (c'est ce qu'affiche le Finder sur l'icône du fichier) :
/// on s'y abonne, sans lire le dossier.
@Observable
@MainActor
final class DownloadMonitor {
    private final class Item {
        let progress: Progress
        var name: String
        init(progress: Progress, name: String) {
            self.progress = progress
            self.name = name
        }
    }

    /// Avancement global (moyenne), `nil` si inconnu.
    private(set) var fraction: Double?
    private(set) var currentName: String?
    private(set) var isDownloading = false
    /// Fichier tout juste terminé, affiché quelques secondes.
    private(set) var finishedName: String?

    var showsActivity: Bool { isDownloading || finishedName != nil }

    @ObservationIgnored private var items: [ObjectIdentifier: Item] = [:]
    @ObservationIgnored private var subscriber: Any?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var finishedTask: Task<Void, Never>?

    private let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

    init() {
        guard let folder else { return }
        subscriber = Progress.addSubscriber(forFileURL: folder) { [weak self] progress in
            let name = Self.displayName(of: progress)
            DispatchQueue.main.async { self?.add(progress, name: name) }
            return {
                DispatchQueue.main.async { self?.remove(progress) }
            }
        }
    }

    func revealDownloads() {
        guard let folder else { return }
        NSWorkspace.shared.open(folder)
    }

    private func add(_ progress: Progress, name: String) {
        items[ObjectIdentifier(progress)] = Item(progress: progress, name: name)
        finishedName = nil
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func remove(_ progress: Progress) {
        guard let item = items.removeValue(forKey: ObjectIdentifier(progress)) else { return }
        // Annulé : on n'annonce rien. Sinon, le fichier est arrivé.
        if !progress.isCancelled {
            finishedName = item.name
            finishedTask?.cancel()
            finishedTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self?.finishedName = nil
            }
        }
        refresh()
    }

    private func refresh() {
        let active = items.values.filter { !$0.progress.isCancelled }
        isDownloading = !active.isEmpty
        if active.isEmpty {
            timer?.invalidate()
            timer = nil
            fraction = nil
            currentName = nil
            return
        }
        let known = active.filter { !$0.progress.isIndeterminate && $0.progress.totalUnitCount > 0 }
        fraction = known.isEmpty ? nil : known.map(\.progress.fractionCompleted).reduce(0, +) / Double(known.count)
        currentName = active.count == 1 ? active.first?.name : "\(active.count) téléchargements"
    }

    private nonisolated static func displayName(of progress: Progress) -> String {
        guard let url = progress.fileURL ?? progress.userInfo[.fileURLKey] as? URL else { return "Fichier" }
        // Safari télécharge dans « fichier.zip.download », Chrome dans « .crdownload ».
        var name = url.lastPathComponent
        for suffix in [".download", ".crdownload", ".part"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        return name
    }
}
