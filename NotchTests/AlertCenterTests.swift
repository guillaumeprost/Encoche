import Foundation
import Testing
@testable import Encoche

/// File d'attente des notifications de l'encoche (sans enregistrement sur le disque).
@MainActor
struct AlertCenterTests {
    private func alert(_ title: String, app: String? = nil, action: NotchAlert.Action? = nil) -> NotchAlert {
        NotchAlert(icon: app.map { .app(bundleID: $0) } ?? .symbol("bell.fill", .gray),
                   source: "Test", title: title, body: nil, action: action)
    }

    private func withButton(_ title: String, _ onPress: @escaping @MainActor () -> Void = {}) -> NotchAlert {
        var alert = alert(title)
        alert.buttons = [.init(label: "OK", role: .primary, action: onPress)]
        return alert
    }

    @Test func showsOneAtATimeAndKeepsHistory() {
        let center = AlertCenter(savesHistory: false)
        center.post(alert("A"))
        center.post(alert("B"))
        #expect(center.current?.title == "A")
        #expect(center.history.map(\.title) == ["B", "A"])
        #expect(center.unreadCount == 2)
        center.markAllRead()
        #expect(center.unreadCount == 0)
    }

    @Test func nextAlertShowsAfterTheNotchFolds() async throws {
        let center = AlertCenter(savesHistory: false)
        center.post(alert("A"))
        center.post(alert("B"))
        center.dismiss()
        #expect(center.current == nil)
        try await Task.sleep(for: .milliseconds(600))
        #expect(center.current?.title == "B")
    }

    @Test func requestsSkipHistoryAndJumpTheQueue() async throws {
        let center = AlertCenter(savesHistory: false)
        center.post(alert("A"))
        center.post(alert("B"))
        center.post(withButton("Question"))
        #expect(!center.history.contains { $0.title == "Question" })
        center.dismiss()
        try await Task.sleep(for: .milliseconds(600))
        #expect(center.current?.title == "Question")
    }

    @Test func mutedAppsAreDroppedAndRecentDuplicatesRemoved() {
        let center = AlertCenter(savesHistory: false)
        center.post(alert("Relayée", app: "com.anthropic.claudefordesktop"))
        center.post(alert("Autre", app: "com.apple.mail"))
        center.muteRelayedNotifications(from: "com.anthropic.claudefordesktop")
        #expect(center.current == nil)
        #expect(center.history.map(\.title) == ["Autre"])
        center.post(alert("Encore", app: "com.anthropic.claudefordesktop"))
        #expect(center.history.map(\.title) == ["Autre"])
    }

    @Test func dismissByIDRemovesShownOrQueuedAlerts() {
        let center = AlertCenter(savesHistory: false)
        let shown = alert("A")
        let queued = alert("B")
        center.post(shown)
        center.post(queued)
        center.dismiss(alertID: queued.id)
        center.dismiss(alertID: shown.id)
        #expect(center.current == nil)
    }

    @Test func clickRunsTheActionAndCloses() {
        let center = AlertCenter(savesHistory: false)
        var ran = false
        center.post(alert("A", action: .run { ran = true }))
        center.activate()
        #expect(ran)
        #expect(center.current == nil)
    }

    @Test func clickWithoutActionDoesNothing() {
        let center = AlertCenter(savesHistory: false)
        center.post(alert("A"))
        center.activate()
        #expect(center.current?.title == "A")
    }

    @Test func buttonsRunAndClose() {
        let center = AlertCenter(savesHistory: false)
        var pressed = false
        center.post(withButton("Question") { pressed = true })
        let button = try! #require(center.current?.buttons.first)
        center.press(button)
        #expect(pressed)
        #expect(center.current == nil)
    }

    @Test func recentTitlesAndHistoryEditing() {
        let center = AlertCenter(savesHistory: false)
        let a = alert("A")
        center.post(a)
        #expect(center.hasRecent(title: "A"))
        #expect(!center.hasRecent(title: "B"))
        center.removeFromHistory(a)
        #expect(center.history.isEmpty)
        center.post(alert("B"))
        center.clearHistory()
        #expect(center.history.isEmpty)
        #expect(center.unreadCount == 0)
    }
}
