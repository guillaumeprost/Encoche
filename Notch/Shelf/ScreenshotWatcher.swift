import AppKit
import Observation
import QuickLookThumbnailing

/// Dernières captures d'écran, trouvées par Spotlight (`kMDItemIsScreenCapture`) :
/// peu importe le dossier ou la langue du nom de fichier, et mise à jour en direct
/// dès qu'une nouvelle capture est enregistrée.
@Observable
@MainActor
final class ScreenshotWatcher {
    static let limit = 20

    struct Screenshot: Identifiable, Equatable {
        let url: URL
        let date: Date
        var id: URL { url }
    }

    private(set) var screenshots: [Screenshot] = []
    private(set) var thumbnails: [URL: NSImage] = [:]

    private let query = NSMetadataQuery()

    init() {
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSCreationDateKey, ascending: false)]

        let center = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            center.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        query.start()
    }

    private func refresh() {
        query.disableUpdates()
        defer { query.enableUpdates() }

        var found: [Screenshot] = []
        for case let item as NSMetadataItem in query.results {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  FileManager.default.fileExists(atPath: path) else { continue }
            let date = item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date ?? .distantPast
            found.append(Screenshot(url: URL(fileURLWithPath: path), date: date))
            if found.count == Self.limit { break }
        }
        found.sort { $0.date > $1.date }
        guard found != screenshots else { return }
        screenshots = found
        thumbnails = thumbnails.filter { url, _ in found.contains { $0.url == url } }
        found.forEach(loadThumbnail)
    }

    private func loadThumbnail(for screenshot: Screenshot) {
        guard thumbnails[screenshot.url] == nil else { return }
        let request = QLThumbnailGenerator.Request(
            fileAt: screenshot.url,
            size: CGSize(width: 200, height: 130),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let image = representation?.nsImage else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.thumbnails[screenshot.url] = image }
            }
        }
    }
}
