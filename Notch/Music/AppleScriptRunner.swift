import AppKit

/// Exécute de petits scripts AppleScript en gardant les versions compilées en cache.
@MainActor
enum AppleScriptRunner {
    private static var cache: [String: NSAppleScript] = [:]

    @discardableResult
    static func run(_ source: String) -> NSAppleEventDescriptor? {
        let script: NSAppleScript
        if let cached = cache[source] {
            script = cached
        } else if let compiled = NSAppleScript(source: source) {
            cache[source] = compiled
            script = compiled
        } else {
            return nil
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            NSLog("[Notch] AppleScript error: \(error)")
            return nil
        }
        return result
    }
}
