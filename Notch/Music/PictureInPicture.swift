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
        let code = AppleScriptRunner.escape(javascript)
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
        // Par la file des scripts d'Encoche : délai maximal, et jamais en même temps qu'un autre.
        let (result, error) = await AppleScriptRunner.runReportingError(source)
        if let error {
            // « You must enable 'Allow JavaScript from Apple Events'… »
            if error.localizedCaseInsensitiveContains("JavaScript") { return .needsJavaScriptPermission(browser: browserName) }
            return .failed
        }
        return result?.stringValue == "none" ? .failed : .done
    }

    // MARK: - Menu du bouton son de Safari

    /// Clic droit sur le bouton son de la barre d'adresse, puis « Image dans l'image ».
    private static func pressSafariMenuItem() -> Bool {
        guard AXIsProcessTrusted(),
            let safariApp = NSRunningApplication.runningApplications(withBundleIdentifier: safari).first
        else { return false }
        let app = AX.app(safariApp.processIdentifier)
        // Le bouton est dans la barre d'outils : on ne descend pas dans les pages web.
        guard
            let button = AX.elements(app, kAXWindowsAttribute).lazy.compactMap({ window in
                AX.first(in: window, maxDepth: 7, skipping: ["AXWebArea"]) { element in
                    guard AX.role(element) == "AXButton", let text = AX.string(element, kAXDescriptionAttribute) else { return false }
                    return ["son de cet onglet", "audio in this tab", "mute this tab"].contains {
                        text.localizedCaseInsensitiveContains($0)
                    }
                }
            }).first
        else { return false }

        AXUIElementPerformAction(button, "AXShowMenu" as CFString)
        // Le menu met un instant à s'ouvrir.
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.05)
            let roots = AX.children(button) + AX.children(app)
            if let item = roots.lazy.compactMap({ root in
                AX.first(in: root, maxDepth: 4) { element in
                    guard AX.role(element) == "AXMenuItem", let title = AX.string(element, kAXTitleAttribute) else { return false }
                    return title.localizedCaseInsensitiveContains("image dans l")
                        || title.localizedCaseInsensitiveContains("picture in picture")
                }
            }).first {
                return AX.press(item)
            }
        }
        // Pas d'entrée « Image dans l'image » : on referme le menu.
        AX.press(key: 53, to: safariApp.processIdentifier) // Échap
        return false
    }
}
