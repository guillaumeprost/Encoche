import AppKit

/// Image dans l'image pour une vidéo qui joue dans le navigateur (YouTube…).
///
/// Safari : on passe d'abord par le menu du bouton son de la barre d'adresse
/// (« Image dans l'image »), via l'Accessibilité, sans réglage particulier. À défaut, un
/// petit script dans l'onglet, qui demande d'autoriser le JavaScript des Apple Events dans
/// les réglages Développeur du navigateur. Chrome et ses dérivés : le script seulement.
enum PictureInPicture {
    enum Outcome: Equatable {
        case done
        /// Le navigateur refuse les scripts : l'option est à activer dans ses réglages.
        case needsJavaScriptPermission(browser: String)
        case failed
    }

    static let safari = "com.apple.Safari"
    static let chromiumBrowsers: Set<String> = [
        "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser", "com.vivaldi.Vivaldi",
    ]

    static func isSupported(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleID == safari || chromiumBrowsers.contains(bundleID)
    }

    static func toggle(in bundleID: String) async -> Outcome {
        if bundleID == safari {
            if await Task.detached(operation: { pressSafariMenuItem() }).value { return .done }
            return await runScript(in: bundleID, browserName: "Safari")
        }
        guard chromiumBrowsers.contains(bundleID) else { return .failed }
        let name = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName ?? "Chrome"
        return await runScript(in: bundleID, browserName: name)
    }

    // MARK: - Script dans l'onglet

    /// Entre en image dans l'image, ou en sort, pour la première vidéo de la page.
    private static let javascript = """
    (() => { const v = [...document.querySelectorAll('video')].find(v => !v.paused) || document.querySelector('video');
      if (!v) return 'none';
      if (document.pictureInPictureElement) { document.exitPictureInPicture(); return 'off'; }
      if (v.webkitSetPresentationMode) { v.webkitSetPresentationMode(v.webkitPresentationMode === 'picture-in-picture' ? 'inline' : 'picture-in-picture'); return 'on'; }
      v.requestPictureInPicture(); return 'on'; })()
    """

    private static func runScript(in bundleID: String, browserName: String) async -> Outcome {
        let code = javascript.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        // L'onglet où joue la vidéo : YouTube en priorité, sinon l'onglet actif.
        let source: String
        if bundleID == safari {
            source = """
            tell application id "\(bundleID)"
                set target to current tab of front window
                repeat with w in windows
                    repeat with t in tabs of w
                        if URL of t contains "youtube.com/watch" then set target to t
                    end repeat
                end repeat
                return do JavaScript "\(code)" in target
            end tell
            """
        } else {
            source = """
            tell application id "\(bundleID)"
                set target to active tab of front window
                repeat with w in windows
                    repeat with t in tabs of w
                        if URL of t contains "youtube.com/watch" then set target to t
                    end repeat
                end repeat
                return execute target javascript "\(code)"
            end tell
            """
        }
        let result = await Task.detached { () -> (String?, String?) in
            var error: NSDictionary?
            let output = NSAppleScript(source: source)?.executeAndReturnError(&error)
            return (output?.stringValue, error?[NSAppleScript.errorMessage] as? String)
        }.value
        if let message = result.1 {
            // « You must enable 'Allow JavaScript from Apple Events'… »
            if message.localizedCaseInsensitiveContains("JavaScript") { return .needsJavaScriptPermission(browser: browserName) }
            return .failed
        }
        return result.0 == "none" ? .failed : .done
    }

    // MARK: - Menu du bouton son de Safari

    /// Clic droit sur le bouton son de la barre d'adresse, puis « Image dans l'image ».
    private static func pressSafariMenuItem() -> Bool {
        guard AXIsProcessTrusted(),
              let safariApp = NSRunningApplication.runningApplications(withBundleIdentifier: safari).first else { return false }
        let app = AXUIElementCreateApplication(safariApp.processIdentifier)
        let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        guard let button = windows.lazy.compactMap({ findAudioButton(in: $0) }).first else { return false }

        AXUIElementPerformAction(button, "AXShowMenu" as CFString)
        // Le menu met un instant à s'ouvrir.
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.05)
            let roots = children(button) + children(app)
            if let item = roots.lazy.compactMap({ findPictureInPictureItem(in: $0) }).first {
                AXUIElementPerformAction(item, kAXPressAction as CFString)
                return true
            }
        }
        // Pas d'entrée « Image dans l'image » : on referme le menu.
        CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)?.postToPid(safariApp.processIdentifier)
        CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)?.postToPid(safariApp.processIdentifier)
        return false
    }

    private static func findAudioButton(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        let role = attribute(element, kAXRoleAttribute) as? String
        if role == "AXWebArea" { return nil }
        if role == "AXButton", let text = attribute(element, kAXDescriptionAttribute) as? String,
           text.localizedCaseInsensitiveContains("son de cet onglet") || text.localizedCaseInsensitiveContains("audio in this tab")
            || text.localizedCaseInsensitiveContains("mute this tab") {
            return element
        }
        guard depth < 7 else { return nil }
        for child in children(element) {
            if let found = findAudioButton(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    private static func findPictureInPictureItem(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        if attribute(element, kAXRoleAttribute) as? String == "AXMenuItem",
           let title = attribute(element, kAXTitleAttribute) as? String,
           title.localizedCaseInsensitiveContains("image dans l") || title.localizedCaseInsensitiveContains("picture in picture") {
            return element
        }
        guard depth < 4 else { return nil }
        for child in children(element) {
            if let found = findPictureInPictureItem(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return value
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
}
