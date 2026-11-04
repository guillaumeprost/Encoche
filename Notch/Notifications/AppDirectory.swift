import AppKit

/// Retrouve une app d'après le nom affiché par une notification (« Calendrier », « Mail »…).
///
/// Ce nom est localisé : il ne correspond pas forcément au nom du fichier (Calendar.app).
/// On cherche d'abord parmi les apps ouvertes, puis dans les dossiers d'applications.
@MainActor
enum AppDirectory {
    private static var cache: [String: String]?

    static func bundleID(forName name: String) -> String? {
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }) {
            return running.bundleIdentifier
        }
        return installedApps()[name]
    }

    /// Nom affiché → identifiant, pour les apps installées (lu une seule fois).
    private static func installedApps() -> [String: String] {
        if let cache { return cache }
        var result: [String: String] = [:]
        let fileManager = FileManager.default
        let folders = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                       fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        for folder in folders {
            for item in (try? fileManager.contentsOfDirectory(atPath: folder)) ?? [] where item.hasSuffix(".app") {
                let path = (folder as NSString).appendingPathComponent(item)
                guard let bundleID = Bundle(path: path)?.bundleIdentifier else { continue }
                let displayName = fileManager.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
                result[displayName] = result[displayName] ?? bundleID
            }
        }
        cache = result
        return result
    }
}
