import Foundation
import Testing
@testable import Encoche

/// Paroles, minuteur, réunions, consommation, Concentration, raccourcis Maison.
struct UtilityTests {
    @Test func parsesSyncedLyrics() {
        let lines = MusicExtras.parse("[00:01.50] Bonjour\n[00:03.00]\n[01:02.25] Fin", synced: true)
        #expect(lines.map(\.text) == ["Bonjour", "♪", "Fin"])
        #expect(lines.map(\.time) == [1.5, 3.0, 62.25])
    }

    @Test func parsesPlainLyricsWithoutBlankLines() {
        let lines = MusicExtras.parse("\nUn\n\nDeux", synced: false)
        #expect(lines.map(\.text) == ["Un", "Deux"])
        #expect(lines.allSatisfy { $0.time == nil })
    }

    @Test func meetingCountdown() {
        let now = Date()
        #expect(MeetingCountdown.short(until: now.addingTimeInterval(8 * 60), now: now) == "8 min")
        #expect(MeetingCountdown.short(until: now.addingTimeInterval(45), now: now) == "45 s")
        #expect(MeetingCountdown.short(until: now.addingTimeInterval(-5), now: now) == "0 s")
    }

    @Test func usageFormat() {
        #expect(ClaudeUsage.format(950) == "950")
        #expect(ClaudeUsage.format(845_000) == "845 k")
        #expect(ClaudeUsage.format(132_708_513) == "132,7 M")
    }

    @Test func usageTotalsAdd() {
        let a = ClaudeUsage.Totals(input: 1, output: 2, cacheWrite: 3, cacheRead: 4)
        #expect((a + a).total == 20)
    }

    @Test func focusSymbolsFallBackOnMac() {
        #expect(FocusMonitor.macSymbol(for: "moon.fill") == "moon.fill")
        // Symbole de l'iPhone absent sur Mac : variante sans « person. ».
        #expect(FocusMonitor.macSymbol(for: "person.lanyardcard.fill") == "lanyardcard.fill")
        #expect(FocusMonitor.macSymbol(for: "symbole.inexistant") == "moon.fill")
        #expect(FocusMonitor.macSymbol(for: nil) == "moon.fill")
    }

    @Test func homeShortcutIconsMatchWholeWords() {
        #expect(HomeShortcutStyle(name: "Lumière salon").symbol == "lightbulb.fill")
        #expect(HomeShortcutStyle(name: "Scène soirée").symbol == "moon.fill")
        // « accessoire » contient « soir » mais n'est pas le soir.
        #expect(HomeShortcutStyle(name: "Activer l'accessoire").symbol == "sparkles")
    }

    @MainActor @Test func timerCountsDownAndPauses() {
        UserDefaults.standard.removeObject(forKey: "runningTimer")
        let timer = TimerController()
        defer { timer.stop() }
        timer.start(minutes: 10, kind: .pomodoro)
        #expect(timer.isActive)
        #expect(abs(timer.remaining(at: Date()) - 600) < 2)
        #expect(timer.fraction(at: Date()) > 0.99)
        #expect(timer.tint(remaining: 300) == .orange)
        #expect(timer.tint(remaining: 30) == .red)

        timer.pause()
        #expect(timer.isPaused)
        let paused = timer.remaining(at: Date())
        #expect(timer.remaining(at: Date().addingTimeInterval(60)) == paused)
        timer.resume()
        #expect(!timer.isPaused)
    }

    @MainActor @Test func timerSurvivesARestart() {
        UserDefaults.standard.removeObject(forKey: "runningTimer")
        let first = TimerController()
        first.start(minutes: 5, kind: .pause)
        let restored = TimerController()
        #expect(restored.isActive)
        #expect(restored.kind == .pause)
        #expect(restored.tint(remaining: 30) == .teal)
        first.stop()
        #expect(UserDefaults.standard.dictionary(forKey: "runningTimer") == nil)
        restored.stop()
    }
}
