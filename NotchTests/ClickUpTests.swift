import Foundation
import SwiftUI
import Testing

@testable import Encoche

struct ClickUpTests {
    private func task(_ id: String, due: Date?, hasTime: Bool = false, type: String = "open", priority: Int? = nil)
        -> ClickUpTask
    {
        ClickUpTask(
            id: id, name: id, status: "", statusType: type, statusColor: .gray, due: due, hasTime: hasTime,
            priority: priority, listID: "l", listName: "")
    }

    @Test func parsesAPITask() throws {
        let json: [String: Any] = [
            "id": "1247bx09ckb",
            "name": "Organiser les tests",
            "status": ["status": "🛠️ at work", "color": "#7b68ee", "type": "custom"],
            "priority": ["id": "1", "priority": "urgent", "color": "#f50000"],
            "due_date": "1793674800000",
            "due_date_time": false,
            "list": ["id": "901510070290", "name": "Tech task"],
        ]
        let parsed = try #require(ClickUpController.makeTask(json))
        #expect(parsed.status == "🛠️ at work")
        #expect(parsed.isInProgress)
        #expect(parsed.priority == 1)
        #expect(parsed.listName == "Tech task")
        #expect(parsed.due == Date(timeIntervalSince1970: 1_793_674_800))
        #expect(!parsed.hasTime)
    }

    @Test func parsesTaskWithoutDueDateOrPriority() throws {
        let json: [String: Any] = ["id": "a", "name": "", "status": ["status": "to do", "type": "open"], "priority": NSNull()]
        let parsed = try #require(ClickUpController.makeTask(json))
        #expect(parsed.name == "Sans titre")
        #expect(parsed.due == nil)
        #expect(parsed.priority == nil)
    }

    @Test func keepsTodayOverdueAndInProgress() {
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        #expect(ClickUpController.isRelevant(task("late", due: today.addingTimeInterval(-86_400)), now: now))
        #expect(ClickUpController.isRelevant(task("today", due: today.addingTimeInterval(3600)), now: now))
        #expect(ClickUpController.isRelevant(task("doing", due: nil, type: "custom"), now: now))
        #expect(!ClickUpController.isRelevant(task("later", due: today.addingTimeInterval(3 * 86_400)), now: now))
        #expect(!ClickUpController.isRelevant(task("todo", due: nil), now: now))
        #expect(!ClickUpController.isRelevant(task("done", due: today, type: "done"), now: now))
    }

    @Test func overdueThenAllDayThenTimedThenUndated() {
        let today = Calendar.current.startOfDay(for: Date())
        let list = [
            task("doing", due: nil, type: "custom"),
            task("timed", due: today.addingTimeInterval(9 * 3600), hasTime: true),
            task("all-day-low", due: today, priority: 4),
            task("all-day-urgent", due: today, priority: 1),
            task("yesterday", due: today.addingTimeInterval(-86_400)),
        ].sorted { ClickUpController.order($0, $1, today: today) }
        #expect(list.map(\.id) == ["yesterday", "all-day-urgent", "all-day-low", "timed", "doing"])
    }

    @Test func picksClosedStatusThenDone() {
        let statuses: [[String: Any]] = [
            ["status": "to do", "type": "open"],
            ["status": "complete", "type": "done"],
            ["status": "Closed", "type": "closed"],
        ]
        #expect(ClickUpController.doneStatus(in: statuses) == "Closed")
        #expect(ClickUpController.doneStatus(in: Array(statuses.prefix(2))) == "complete")
        #expect(ClickUpController.doneStatus(in: [statuses[0]]) == nil)
    }

    @Test func hexColor() {
        #expect(Color(hex: "#7b68ee") != nil)
        #expect(Color(hex: "nope") == nil)
        #expect(Color(hex: nil) == nil)
    }

    @Test func remindsOnceShortlyBeforeATimedDueDate() {
        let now = Date()
        let soon = task("soon", due: now.addingTimeInterval(4 * 60), hasTime: true)
        let later = task("later", due: now.addingTimeInterval(20 * 60), hasTime: true)
        let allDay = task("all-day", due: now.addingTimeInterval(60), hasTime: false)
        let longPast = task("past", due: now.addingTimeInterval(-10 * 60), hasTime: true)
        var done = task("done", due: now.addingTimeInterval(60), hasTime: true)
        done.isCompleted = true
        let list = [soon, later, allDay, longPast, done]
        #expect(ClickUpController.tasksDueSoon(list, now: now, alreadyAlerted: []).map(\.id) == ["soon"])
        let alerted: Set = [ClickUpController.alertKey(soon)]
        #expect(ClickUpController.tasksDueSoon(list, now: now, alreadyAlerted: alerted).isEmpty)
    }

    @Test func newTasksAreDueTodayAtNoon() throws {
        let now = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 23)))
        let due = Date(timeIntervalSince1970: Double(ClickUpController.todayDueDate(now: now)) / 1000)
        #expect(Calendar.current.isDate(due, inSameDayAs: now))
        #expect(Calendar.current.component(.hour, from: due) == 12)
    }

    @Test func parsesLists() {
        let lists = ClickUpController.makeLists(
            [["id": "901509759456", "name": "Personal List"], ["name": "sans id"]], path: "Perso")
        #expect(lists == [ClickUpList(id: "901509759456", name: "Personal List", path: "Perso")])
    }

    @Test func parsesUpdateDateAndKeepsMostRecentFirst() throws {
        let parsed = try #require(ClickUpController.makeTask(["id": "a", "name": "a", "date_updated": "1794538800000"]))
        #expect(parsed.updated == Date(timeIntervalSince1970: 1_794_538_800))

        var old = task("old", due: nil)
        old.updated = Date(timeIntervalSince1970: 100)
        var new = task("new", due: nil)
        new.updated = Date(timeIntervalSince1970: 200)
        let never = task("never", due: nil)
        #expect(ClickUpController.mostRecent([old, never, new]).map(\.id) == ["new", "old", "never"])
        #expect(ClickUpController.mostRecent([old, never, new], limit: 1).map(\.id) == ["new"])
    }

    @Test func throttlesRefreshesWithinTheMinimumInterval() {
        let now = Date()
        let interval = ClickUpController.minimumRefreshInterval
        #expect(ClickUpController.shouldRefresh(lastRefresh: nil, now: now, minimumInterval: interval))
        #expect(!ClickUpController.shouldRefresh(lastRefresh: now.addingTimeInterval(-5), now: now, minimumInterval: interval))
        #expect(ClickUpController.shouldRefresh(lastRefresh: now.addingTimeInterval(-20), now: now, minimumInterval: interval))
        // Sans délai (minuteur, coche, nouveau jeton) : toujours.
        #expect(ClickUpController.shouldRefresh(lastRefresh: now, now: now, minimumInterval: 0))
    }

    @Test func splitsLateTasksFromTodayAndInProgress() {
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        let tasks = [
            task("late", due: today.addingTimeInterval(-86_400)),
            task("today", due: today.addingTimeInterval(3600), hasTime: true),
            task("doing", due: nil, type: "custom"),
        ]
        let (late, current) = ClickUpController.split(tasks, now: now)
        #expect(late.map(\.id) == ["late"])
        #expect(current.map(\.id) == ["today", "doing"])
    }

    @Test func postponementDates() throws {
        let calendar = Calendar.current
        // Mercredi 18 novembre 2026, 9 h.
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 9)))
        let tomorrow = try #require(ClickUpController.dueDate(for: .tomorrow, now: now))
        #expect(calendar.component(.day, from: tomorrow) == 19)
        #expect(calendar.component(.hour, from: tomorrow) == 12)
        let monday = try #require(ClickUpController.dueDate(for: .nextMonday, now: now))
        #expect(calendar.component(.weekday, from: monday) == 2)
        #expect(calendar.component(.day, from: monday) == 23)
        #expect(ClickUpController.dueDate(for: .none, now: now) == nil)

        // Un lundi : le lundi d'après, pas le jour même.
        let aMonday = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 9)))
        let next = try #require(ClickUpController.dueDate(for: .nextMonday, now: aMonday))
        #expect(calendar.component(.day, from: next) == 23)
    }

    @Test func undatedTasksFollowTheChosenStatuses() {
        let now = Date()
        func undated(_ id: String, status: String) -> ClickUpTask {
            ClickUpTask(
                id: id, name: id, status: status, statusType: "custom", statusColor: .gray, due: nil, hasTime: false,
                priority: nil, listID: "l", listName: "")
        }
        let doing = undated("doing", status: "🛠️ at work")
        let todo = undated("todo", status: "📥 todo")
        // Sans choix : tous les statuts intermédiaires.
        #expect(ClickUpController.isRelevant(todo, now: now, activeStatuses: nil))
        let chosen: Set = ["🛠️ at work"]
        #expect(ClickUpController.isRelevant(doing, now: now, activeStatuses: chosen))
        #expect(!ClickUpController.isRelevant(todo, now: now, activeStatuses: chosen))
        // Une échéance du jour l'emporte sur le statut.
        var todoToday = todo
        todoToday.due = now
        #expect(ClickUpController.isRelevant(todoToday, now: now, activeStatuses: chosen))
    }

    @Test func listsCustomStatusesMostFrequentFirst() {
        func withStatus(_ id: String, _ status: String, type: String = "custom") -> ClickUpTask {
            ClickUpTask(
                id: id, name: id, status: status, statusType: type, statusColor: .gray, due: nil, hasTime: false,
                priority: nil, listID: "l", listName: "")
        }
        let statuses = ClickUpController.customStatuses(in: [
            withStatus("a", "📥 todo"), withStatus("b", "🛠️ at work"), withStatus("c", "📥 Todo"),
            withStatus("d", "backlog", type: "open"),
        ])
        #expect(statuses.map(\.id) == ["📥 todo", "🛠️ at work"])
    }
}
