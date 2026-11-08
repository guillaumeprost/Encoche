import Foundation
import SwiftUI
import Testing

@testable import Encoche

struct RemindersTests {
    private func reminder(_ id: String, due: Date?, hasTime: Bool) -> TodayReminder {
        TodayReminder(id: id, title: id, due: due, hasTime: hasTime, list: "", color: .orange)
    }

    @Test func overdueThenAllDayThenTimed() {
        let today = Calendar.current.startOfDay(for: Date())
        let list = [
            reminder("timed-late", due: today.addingTimeInterval(18 * 3600), hasTime: true),
            reminder("all-day", due: today, hasTime: false),
            reminder("timed-early", due: today.addingTimeInterval(9 * 3600), hasTime: true),
            reminder("yesterday", due: today.addingTimeInterval(-86_400), hasTime: false),
        ].sorted { RemindersController.order($0, $1, today: today) }
        #expect(list.map(\.id) == ["yesterday", "all-day", "timed-early", "timed-late"])
    }

    @Test func overdueDetection() {
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        #expect(reminder("a", due: today.addingTimeInterval(-86_400), hasTime: false).isOverdue(now: now))
        #expect(!reminder("b", due: today, hasTime: false).isOverdue(now: now))
        #expect(reminder("c", due: now.addingTimeInterval(-60), hasTime: true).isOverdue(now: now))
        var done = reminder("d", due: today.addingTimeInterval(-86_400), hasTime: false)
        done.isCompleted = true
        #expect(!done.isOverdue(now: now))
    }
}
