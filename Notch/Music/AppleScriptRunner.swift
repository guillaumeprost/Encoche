import AppKit

/// Exécute de petits scripts AppleScript (Musique, Spotify) **hors du fil principal**, avec
/// un délai maximal.
///
/// Une app qui ne répond plus (Musique figée…) bloquait sinon l'encoche entière en attendant
/// sa réponse — y compris au lancement. Les scripts passent par une file dédiée (NSAppleScript
/// n'aime pas être utilisé depuis plusieurs fils à la fois) et abandonnent au bout de 2 s.
enum AppleScriptRunner {
    private static let queue = DispatchQueue(label: "com.guillaumeprost.notch.applescript", qos: .userInitiated)
    /// Scripts compilés, utilisés seulement depuis `queue`.
    nonisolated(unsafe) private static var cache: [String: NSAppleScript] = [:]
    private static let timeoutSeconds = 2

    /// Renvoie le résultat, ou `nil` en cas d'erreur ou si l'app ne répond pas à temps.
    @discardableResult
    static func run(_ source: String) async -> NSAppleEventDescriptor? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: execute(source))
            }
        }
    }

    private static func execute(_ source: String) -> NSAppleEventDescriptor? {
        let script: NSAppleScript
        if let cached = cache[source] {
            script = cached
        } else {
            let wrapped = "with timeout of \(timeoutSeconds) seconds\n\(source)\nend timeout"
            guard let compiled = NSAppleScript(source: wrapped) else { return nil }
            cache[source] = compiled
            script = compiled
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            NSLog("[Encoche] AppleScript error: \(error)")
            return nil
        }
        return result
    }
}
