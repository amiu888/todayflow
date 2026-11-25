import Foundation
import Testing
import TodayFlowCore
@testable import TodayFlowPhone

@MainActor
@Suite("iPhone app")
struct PhoneTests {
    private func environment() -> PhoneEnvironment { PhoneEnvironment.makeInMemory() }

    private func addTask(_ env: PhoneEnvironment, _ title: String, dueIn hours: Double, priority: Priority = .normal) async throws -> WorkItem {
        let due = Date.now.addingTimeInterval(hours * 3600)
        return try await CreateTask(repository: env.workItems, calendar: env.workCalendar)
            .execute(.init(title: title, startAt: due.addingTimeInterval(-1800), endAt: due, priority: priority))
    }

    // MARK: Notifications

    @Test func nudgesAt12h5hAnd1hBeforeDue() async throws {
        let env = environment()
        let item = try await addTask(env, "Budget draft", dueIn: 20)
        let controller = PhoneNotificationController(environment: env)
        let ids = await controller.plannedRequests(now: .now).map(\.identifier)
        #expect(ids == ["nudge.\(item.id)-12", "nudge.\(item.id)-5", "nudge.\(item.id)-1"])
    }

    @Test func onlyFutureStagesAreScheduled() async throws {
        let env = environment()
        let item = try await addTask(env, "Soon", dueIn: 3)
        let controller = PhoneNotificationController(environment: env)
        let ids = await controller.plannedRequests(now: .now).map(\.identifier)
        #expect(ids == ["nudge.\(item.id)-1"])
    }

    @Test func doneTasksAndSwitchedOffNudgesGetNothing() async throws {
        let env = environment()
        let item = try await addTask(env, "Done already", dueIn: 20)
        _ = try await CompleteTask(repository: env.workItems, linkRepository: env.links).execute(item.id, at: .now)
        let controller = PhoneNotificationController(environment: env)
        #expect(await controller.plannedRequests(now: .now).isEmpty)

        _ = try await addTask(env, "Open", dueIn: 20)
        controller.settings.nudgesOn = false
        #expect(await controller.plannedRequests(now: .now).isEmpty)
        controller.settings.nudgesOn = true
    }

    @Test func remindersReplaceTheOneHourNudge() async throws {
        let env = environment()
        let item = try await addTask(env, "Call supplier", dueIn: 20)
        let fireAt = Date.now.addingTimeInterval(2 * 3600)
        try await env.reminders.save(Reminder(itemId: item.id, kind: .task, fireAt: fireAt))
        let controller = PhoneNotificationController(environment: env)
        let requests = await controller.plannedRequests(now: .now)
        #expect(requests.first?.identifier.hasPrefix("reminder.") == true)
        #expect(!requests.map(\.identifier).contains("nudge.\(item.id)-1"))
        #expect(requests.first?.content.categoryIdentifier == PhoneNotificationController.categoryID)
        #expect(requests.first?.content.userInfo[PhoneNotificationController.itemIdKey] as? String == item.id.description)
    }

    @Test func completeAndTomorrowActionsChangeTheTask() async throws {
        let env = environment()
        let a = try await addTask(env, "A", dueIn: 2)
        let b = try await addTask(env, "B", dueIn: 2)
        let controller = PhoneNotificationController(environment: env)
        await controller.handle(action: PhoneNotificationController.Action.complete, raw: a.id.description)
        #expect(await env.workItems.item(a.id)?.status.isComplete == true)
        await controller.handle(action: PhoneNotificationController.Action.tomorrow, raw: b.id.description)
        let moved = try #require(await env.workItems.item(b.id))
        #expect(moved.endAt > b.endAt)

        var opened: UUIDv7?
        await controller.handle(action: PhoneNotificationController.Action.open, raw: a.id.description)
        #expect(controller.pendingOpen == a.id)
        controller.onOpen = { opened = $0 }
        #expect(opened == a.id)
        #expect(controller.pendingOpen == nil)
    }

    // MARK: Share inbox

    @Test func sharedLinkAndPhotoBecomeTasks() async throws {
        let env = environment()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("phone-inbox-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = ShareInbox(directory: root.appendingPathComponent("Inbox"))
        let photo = root.appendingPathComponent("Whiteboard.png")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: photo)

        _ = try inbox.add(ShareInboxItem(priority: .high, due: .tomorrow, urls: [URL(string: "https://example.com/pricing")!]))
        _ = try inbox.add(ShareInboxItem(title: "Whiteboard from standup"), copying: [photo])

        let ids = await PhoneInboxImporter.importPending(env, inbox: inbox)
        #expect(ids.count == 2)
        #expect(inbox.pending().isEmpty)

        let items = await env.workItems.allItems()
        let link = try #require(items.first { $0.priority == .high })
        #expect(Calendar.current.isDateInTomorrow(link.endAt))
        let board = try #require(items.first { $0.title == "Whiteboard from standup" })
        let files = await env.attachments.attachments(for: board.id)
        #expect(files.count == 1)
        #expect(files.first?.localCopyPath.map { FileManager.default.fileExists(atPath: $0) } == true)
    }

    // MARK: Quick add and links

    @Test func quickAddSplitsTagsFromTheTitle() {
        let text = "Call Maria tomorrow 3pm #Q4 #q4 #launch"
        #expect(PhoneQuickAdd.title(from: text) == "Call Maria tomorrow 3pm")
        #expect(PhoneQuickAdd.tags(in: text) == ["Q4", "launch"])
    }

    @Test func taskLinksRoundTrip() {
        let id = UUIDv7(timestampMilliseconds: 1_700_000_000_000)
        #expect(PhoneLinks.taskId(from: PhoneLinks.url(for: id)) == id)
        #expect(PhoneLinks.taskId(from: URL(string: "https://example.com/task/x")!) == nil)
    }
}
