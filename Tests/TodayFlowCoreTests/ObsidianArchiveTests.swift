import Foundation
import Testing
@testable import TodayFlowCore

@Suite("Obsidian archive")
struct ObsidianArchiveTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    /// A project with a finished task, a blocker, a contact and a history.
    private func fixture() -> (ObsidianArchiveSnapshot, WorkItem, WorkItem, WorkItem, Contact) {
        let project = WorkItem(
            kind: .project, title: "Launch Q4",
            startAt: date(1, 9), endAt: date(30, 17),
            createdAt: date(1, 9), updatedAt: date(1, 9)
        )
        let task = WorkItem(
            title: "Review Q4 roadmap",
            parentId: project.id,
            descriptionMd: "<!-- note 2026-11-04T16:10:00Z -->\nWaiting on pricing from Maria",
            summary: "Email from Maria about the roadmap.",
            status: .done,
            priority: .high,
            startAt: date(3, 9), endAt: date(6, 17),
            completedAt: date(5, 15, 40),
            tags: ["launch", "Q4 plan"],
            createdAt: date(3, 9, 5), updatedAt: date(5, 15, 40)
        )
        let blocker = WorkItem(
            title: "Pricing sheet",
            parentId: project.id,
            startAt: date(2, 9), endAt: date(4, 17),
            createdAt: date(2, 9), updatedAt: date(2, 9)
        )
        let maria = Contact(firstName: "Maria", lastName: "Silva", company: "Acme", emails: ["maria@example.com"])
        let events = [
            ActivityEvent(itemId: task.id, kind: .dropped, summary: "Dropped from Outlook", sourceApp: "com.microsoft.Outlook", occurredAt: date(3, 9, 5)),
            ActivityEvent(itemId: task.id, kind: .priorityChanged, summary: "Priority → High", occurredAt: date(3, 9, 20)),
            ActivityEvent(itemId: task.id, kind: .reordered, summary: "Reordered", occurredAt: date(3, 9, 21)),
            ActivityEvent(itemId: task.id, kind: .completed, summary: "Completed “Review Q4 roadmap”", occurredAt: date(5, 15, 40)),
        ]
        let snapshot = ObsidianArchiveSnapshot(
            items: [project, task, blocker],
            events: events,
            links: [ItemLink(fromId: blocker.id, toId: task.id, kind: .blocks)],
            contacts: [maria],
            contactTaskIds: [maria.id: [task.id]],
            appNames: ["com.microsoft.Outlook": "Microsoft Outlook"]
        )
        return (snapshot, project, task, blocker, maria)
    }

    @Test func archiveRootSitsNextToTheSyncNote() {
        #expect(ObsidianArchive.root(forNotePath: "TodayFlow/Tasks.md") == "TodayFlow")
        #expect(ObsidianArchive.root(forNotePath: "Tasks.md") == "TodayFlow")
        #expect(ObsidianArchive.root(forNotePath: "Work/Daily/TodayFlow.md") == "Work/Daily/TodayFlow")
    }

    @Test func safeNamesDropCharactersObsidianCannotUse() {
        #expect(ObsidianArchive.safeName("Q4: plan/review [draft] #1?") == "Q4 plan review draft 1")
        #expect(ObsidianArchive.safeName("  ") == "Untitled")
        #expect(ObsidianArchive.safeName(".hidden") == "hidden")
    }

    @Test func writesOneNotePerTaskProjectContactAndDay() throws {
        let (snapshot, project, task, _, maria) = fixture()
        let files = ObsidianArchive.render(snapshot, root: "TodayFlow", calendar: utc)
        let taskPath = try #require(ObsidianArchive.path(for: task.id, snapshot: snapshot, root: "TodayFlow", calendar: utc))
        let projectPath = try #require(ObsidianArchive.path(for: project.id, snapshot: snapshot, root: "TodayFlow", calendar: utc))

        #expect(taskPath.hasPrefix("TodayFlow/Tasks/2026-11/Review Q4 roadmap ("))
        #expect(projectPath.hasPrefix("TodayFlow/Projects/Launch Q4 ("))
        #expect(files.keys.contains { $0.hasPrefix("TodayFlow/Contacts/Maria Silva (") })
        #expect(files["TodayFlow/Daily/2026-11-05.md"] != nil)
        #expect(files["TodayFlow/TodayFlow.base"] != nil)
        // 3 items + 1 contact + the base + days 2, 3 and 5 (creating a project is not day activity).
        #expect(files.count == 8, "\(files.keys.sorted())")
        #expect(files.keys.contains { $0.contains("(\(String(maria.id.description.suffix(6)).lowercased())).md") })
    }

    @Test func taskNoteTellsTheWholeStory() throws {
        let (snapshot, _, task, _, _) = fixture()
        let files = ObsidianArchive.render(snapshot, root: "TodayFlow", calendar: utc)
        let path = try #require(ObsidianArchive.path(for: task.id, snapshot: snapshot, root: "TodayFlow", calendar: utc))
        let note = try #require(files[path])

        #expect(note.contains("todayflow_id: \(task.id)"))
        #expect(note.contains("status: done"))
        #expect(note.contains("priority: high"))
        #expect(note.contains("project: \"[[TodayFlow/Projects/Launch Q4 ("))
        #expect(note.contains("  - \"Q4-plan\""))
        #expect(note.contains("created: 2026-11-03T09:05:00"))
        #expect(note.contains("completed: 2026-11-05T15:40:00"))
        #expect(note.contains("lead_time_days: 2.3"))
        #expect(note.contains("late: false"))
        #expect(note.contains("source_app: \"Microsoft Outlook\""))
        // Timeline, oldest first, without reorder noise.
        #expect(note.contains("- 2026-11-03 09:05 · Dropped from Outlook · from Microsoft Outlook"))
        #expect(note.contains("- 2026-11-03 09:20 · Priority → High"))
        #expect(!note.contains("Reordered"))
        #expect(note.contains("**Outcome:** done after 2.3 days, on time"))
        // People, related work, notes.
        #expect(note.contains("## People\n- [[TodayFlow/Contacts/Maria Silva ("))
        #expect(note.contains("Acme · maria@example.com"))
        #expect(note.contains("- Blocked by: [[TodayFlow/Tasks/2026-11/Pricing sheet ("))
        #expect(note.contains("blocked_by:"))
        #expect(note.contains("Waiting on pricing from Maria"))
        #expect(note.contains("> Email from Maria about the roadmap."))
        #expect(note.contains(ObsidianArchive.footer))
    }

    @Test func dailyNoteAnswersWhatIDidThatDay() throws {
        let (snapshot, _, _, _, _) = fixture()
        let files = ObsidianArchive.render(snapshot, root: "TodayFlow", calendar: utc)
        let created = try #require(files["TodayFlow/Daily/2026-11-03.md"])
        #expect(created.contains("# Tuesday, 3 Nov 2026"))
        #expect(created.contains("## Created (1)"))
        #expect(created.contains("09:05 [[TodayFlow/Tasks/2026-11/Review Q4 roadmap ("))
        #expect(created.contains("from Microsoft Outlook"))
        #expect(created.contains("## Worked on (1)"))
        #expect(created.contains("09:20 [[TodayFlow/Tasks/2026-11/Review Q4 roadmap ("))

        let done = try #require(files["TodayFlow/Daily/2026-11-05.md"])
        #expect(done.contains("## Completed (1)"))
        #expect(done.contains("with [[TodayFlow/Contacts/Maria Silva ("))
        #expect(done.contains("completed: 1"))
    }

    @Test func missedDeadlinesShowOnTheirDay() throws {
        let late = WorkItem(
            title: "Vendor contract",
            startAt: date(18, 9), endAt: date(20, 17),
            createdAt: date(20, 8), updatedAt: date(20, 8)
        )
        let files = ObsidianArchive.render(ObsidianArchiveSnapshot(items: [late]), root: "TodayFlow", calendar: utc)
        let day = try #require(files["TodayFlow/Daily/2026-11-20.md"])
        #expect(day.contains("## Due but not done (1)"))
    }

    @Test func contactNoteListsTheirTasks() throws {
        let (snapshot, _, _, _, maria) = fixture()
        let files = ObsidianArchive.render(snapshot, root: "TodayFlow", calendar: utc)
        let note = try #require(files.first { $0.key.hasPrefix("TodayFlow/Contacts/") }?.value)
        #expect(note.contains("todayflow_id: \(maria.id)"))
        #expect(note.contains("company: \"Acme\""))
        #expect(note.contains("done_tasks: 1"))
        #expect(note.contains("## Completed tasks (1)\n- [x] [[TodayFlow/Tasks/2026-11/Review Q4 roadmap ("))
        #expect(note.contains("last_activity: 2026-11-05T15:40:00"))
    }

    @Test func projectNoteListsOpenAndCompletedTasksAndPeople() throws {
        let (snapshot, project, _, _, _) = fixture()
        let files = ObsidianArchive.render(snapshot, root: "TodayFlow", calendar: utc)
        let path = try #require(ObsidianArchive.path(for: project.id, snapshot: snapshot, root: "TodayFlow", calendar: utc))
        let note = try #require(files[path])
        #expect(note.contains("open_tasks: 1"))
        #expect(note.contains("done_tasks: 1"))
        #expect(note.contains("## Open (1)\n- [ ] [[TodayFlow/Tasks/2026-11/Pricing sheet ("))
        #expect(note.contains("## People\n- [[TodayFlow/Contacts/Maria Silva ("))
    }

    @Test func deletedTasksMoveToTheDeletedFolder() throws {
        var gone = WorkItem(title: "Old idea", createdAt: date(2, 9), updatedAt: date(2, 9))
        gone.deletedAt = date(4, 10)
        let snapshot = ObsidianArchiveSnapshot(items: [], deletedItems: [gone])
        let path = try #require(ObsidianArchive.path(for: gone.id, snapshot: snapshot, root: "TodayFlow", calendar: utc))
        #expect(path.hasPrefix("TodayFlow/Deleted/Old idea ("))
        let note = try #require(ObsidianArchive.render(snapshot, root: "TodayFlow", calendar: utc)[path])
        #expect(note.contains("status: deleted"))
        #expect(note.contains("deleted: 2026-11-04T10:00:00"))
    }

    @Test func deletedWorkStaysOutOfTheDayStory() throws {
        let kept = WorkItem(title: "Real work", createdAt: date(4, 9), updatedAt: date(4, 9))
        var junk = WorkItem(title: "UI test task", createdAt: date(4, 10), updatedAt: date(4, 10))
        junk.deletedAt = date(4, 11)
        let files = ObsidianArchive.render(
            ObsidianArchiveSnapshot(items: [kept], deletedItems: [junk]),
            root: "TodayFlow", calendar: utc
        )
        let day = try #require(files["TodayFlow/Daily/2026-11-04.md"])
        #expect(day.contains("created: 1"))
        #expect(day.contains("## Created (1)"))
        #expect(day.contains("later_deleted: 1"))
        #expect(day.contains("## Later deleted (1)\n[[TodayFlow/Deleted/UI test task ("))
    }

    @Test func unknownAppsFallBackToAReadableName() throws {
        let task = WorkItem(title: "Clip", createdAt: date(4, 9), updatedAt: date(4, 9))
        let snapshot = ObsidianArchiveSnapshot(
            items: [task],
            events: [ActivityEvent(itemId: task.id, kind: .dropped, summary: "Dropped", sourceApp: "com.apple.finder", occurredAt: date(4, 9))]
        )
        let files = ObsidianArchive.render(snapshot, root: "TodayFlow", calendar: utc)
        let path = try #require(ObsidianArchive.path(for: task.id, snapshot: snapshot, root: "TodayFlow", calendar: utc))
        #expect(files[path]?.contains("source_app: \"Finder\"") == true)
    }

    @Test func renderingIsDeterministic() {
        let (snapshot, _, _, _, _) = fixture()
        #expect(
            ObsidianArchive.render(snapshot, root: "TodayFlow", calendar: utc)
                == ObsidianArchive.render(snapshot, root: "TodayFlow", calendar: utc)
        )
    }

    @Test func sameTitlesGetDistinctFiles() {
        let a = WorkItem(title: "Follow up", createdAt: date(2, 9))
        let b = WorkItem(title: "Follow up", createdAt: date(2, 9))
        let snapshot = ObsidianArchiveSnapshot(items: [a, b])
        let pa = ObsidianArchive.path(for: a.id, snapshot: snapshot, root: "TodayFlow", calendar: utc)
        let pb = ObsidianArchive.path(for: b.id, snapshot: snapshot, root: "TodayFlow", calendar: utc)
        #expect(pa != nil && pb != nil && pa != pb)
    }

    @Test func manifestPlansOnlyChangedWritesAndOwnDeletes() {
        var manifest = ObsidianArchiveManifest(target: "local|/v|TodayFlow")
        manifest.files["TodayFlow/a.md"] = ObsidianArchiveManifest.hash("same")
        manifest.files["TodayFlow/b.md"] = ObsidianArchiveManifest.hash("old")
        manifest.files["TodayFlow/renamed.md"] = ObsidianArchiveManifest.hash("x")
        let plan = manifest.plan(for: [
            "TodayFlow/a.md": "same",
            "TodayFlow/b.md": "new",
            "TodayFlow/c.md": "added",
        ])
        #expect(plan.writes == ["TodayFlow/b.md", "TodayFlow/c.md"])
        #expect(plan.deletes == ["TodayFlow/renamed.md"])
    }
}
