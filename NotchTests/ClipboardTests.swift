import AppKit
import Testing

@testable import Encoche

/// Historique du presse-papier, sur un presse-papier et un dossier de test (jamais les tiens).
@MainActor
final class ClipboardTests {
    private let pasteboard = NSPasteboard(name: .init("encoche-test-\(UUID().uuidString)"))
    private let folder = TemporaryFolder()
    private var frontmost: String? = "com.apple.Safari"

    isolated deinit {
        pasteboard.releaseGlobally()
    }

    private func makeController() -> ClipboardController {
        ClipboardController(pasteboard: pasteboard, folder: folder.url, frontmostApp: { [unowned self] in frontmost }, polls: false)
    }

    private func copy(_ text: String, extraType: String? = nil) {
        pasteboard.clearContents()
        if let extraType { pasteboard.setString("", forType: .init(extraType)) }
        pasteboard.setString(text, forType: .string)
    }

    private func copyImage(color: NSColor) {
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            color.setFill()
            rect.fill()
            return true
        }
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    private func texts(_ clipboard: ClipboardController) -> [String] {
        clipboard.sortedItems.compactMap {
            if case .text(let text) = $0.content { return text }
            return nil
        }
    }

    @Test func recordsCopiesNewestFirst() {
        let clipboard = makeController()
        copy("un")
        clipboard.poll()
        copy("deux")
        clipboard.poll()
        #expect(texts(clipboard) == ["deux", "un"])
        #expect(clipboard.items.first?.sourceBundleID == "com.apple.Safari")
    }

    @Test func nothingNewWithoutAChange() {
        let clipboard = makeController()
        copy("un")
        clipboard.poll()
        clipboard.poll()
        #expect(clipboard.items.count == 1)
    }

    @Test func copyingAgainMovesTheItemUp() {
        let clipboard = makeController()
        for text in ["un", "deux", "un"] {
            copy(text)
            clipboard.poll()
        }
        #expect(texts(clipboard) == ["un", "deux"])
    }

    @Test func passwordsAreNeverRecorded() {
        let clipboard = makeController()
        copy("secret", extraType: "org.nspasteboard.ConcealedType")
        clipboard.poll()
        frontmost = "com.apple.Passwords"
        copy("autre secret")
        clipboard.poll()
        #expect(clipboard.items.isEmpty)
    }

    @Test func blankTextIsIgnoredAndLongTextCut() {
        let clipboard = makeController()
        copy("  \n ")
        clipboard.poll()
        #expect(clipboard.items.isEmpty)
        copy(String(repeating: "a", count: ClipboardController.maxTextLength + 50))
        clipboard.poll()
        #expect(texts(clipboard).first?.count == ClipboardController.maxTextLength)
    }

    @Test func pinnedItemsComeFirstAndSurviveClearing() {
        let clipboard = makeController()
        for text in ["un", "deux", "trois"] {
            copy(text)
            clipboard.poll()
        }
        let un = try! #require(clipboard.items.first { $0.content == .text("un") })
        clipboard.togglePin(un)
        #expect(texts(clipboard) == ["un", "trois", "deux"])
        clipboard.clearUnpinned()
        #expect(texts(clipboard) == ["un"])
    }

    @Test func keepsALimitedHistory() {
        let clipboard = makeController()
        for index in 0...ClipboardController.maxUnpinned {
            copy("texte \(index)")
            clipboard.poll()
        }
        #expect(clipboard.items.count == ClipboardController.maxUnpinned)
        #expect(texts(clipboard).last == "texte 1")
    }

    @Test func copyPutsTheItemBackOnThePasteboard() {
        let clipboard = makeController()
        copy("un")
        clipboard.poll()
        copy("deux")
        clipboard.poll()
        let un = try! #require(clipboard.items.last)
        clipboard.copy(un)
        #expect(pasteboard.string(forType: .string) == "un")
        #expect(texts(clipboard) == ["un", "deux"])
        // Notre propre copie n'est pas enregistrée une deuxième fois.
        clipboard.poll()
        #expect(clipboard.items.count == 2)
    }

    @Test func historySurvivesARestart() {
        let clipboard = makeController()
        copy("un")
        clipboard.poll()
        clipboard.togglePin(clipboard.items[0])
        let restored = makeController()
        #expect(restored.items == clipboard.items)
    }

    @Test func imagesAreStoredAndTheirFilesRemoved() throws {
        let clipboard = makeController()
        copyImage(color: .red)
        clipboard.poll()
        let item = try #require(clipboard.items.first)
        let file = try #require(clipboard.imageURL(of: item))
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(clipboard.thumbnail(for: item) != nil)

        clipboard.delete(item)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func clearingRemovesImageFiles() throws {
        let clipboard = makeController()
        copyImage(color: .blue)
        clipboard.poll()
        let file = try #require(clipboard.items.first.flatMap(clipboard.imageURL(of:)))
        clipboard.clearUnpinned()
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
