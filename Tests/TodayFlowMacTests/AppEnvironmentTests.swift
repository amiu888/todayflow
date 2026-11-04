import Foundation
import Testing
import TodayFlowCore
import TodayFlowMac
import TodayFlowRecognition

@MainActor
private struct Fixture {
    let workItems = InMemoryWorkItemRepository()
    let links = InMemoryLinkRepository()
    let attachments = InMemoryAttachmentRepository()
    let settings = InMemorySettingRepository()
    let environment: AppEnvironment

    init(workCalendar: WorkCalendar = .standard) {
        environment = AppEnvironment(
            workItems: workItems,
            links: links,
            attachments: attachments,
            settings: settings,
            pipeline: .standard,
            workCalendar: workCalendar
        )
    }
}

struct AppEnvironmentTests {
    @Test @MainActor
    func init_defaultsToStandardWorkCalendar() {
        let f = Fixture()
        #expect(f.environment.workCalendar.startHour == 9)
        #expect(f.environment.workCalendar.endHour == 17)
        #expect(f.environment.workCalendar.workWeekdays == Set([2, 3, 4, 5, 6]))
    }

    @Test @MainActor
    func init_acceptsCustomWorkCalendar() {
        let custom = WorkCalendar(startHour: 8, endHour: 16, workWeekdays: [2, 3, 4])
        let f = Fixture(workCalendar: custom)
        #expect(f.environment.workCalendar.startHour == 8)
        #expect(f.environment.workCalendar.endHour == 16)
        #expect(f.environment.workCalendar.workWeekdays == Set([2, 3, 4]))
    }

    @Test @MainActor
    func loadSettings_updatesWorkCalendarFromStore() async throws {
        let f = Fixture()
        let stored = WorkCalendarSettings(startHour: 8, endHour: 16, workWeekdays: [2, 3, 4])
        let data = try JSONEncoder().encode(stored)
        try await f.settings.set(String(decoding: data, as: UTF8.self), for: SettingKeys.workCalendar)
        await f.environment.loadSettings()
        #expect(f.environment.workCalendar.startHour == 8)
        #expect(f.environment.workCalendar.endHour == 16)
        #expect(f.environment.workCalendar.workWeekdays == Set([2, 3, 4]))
    }

    @Test @MainActor
    func loadSettings_missingValue_keepsCurrentCalendar() async {
        let f = Fixture()
        await f.environment.loadSettings()
        #expect(f.environment.workCalendar.startHour == 9)
        #expect(f.environment.workCalendar.endHour == 17)
        #expect(f.environment.workCalendar.workWeekdays == Set([2, 3, 4, 5, 6]))
    }

    @Test @MainActor
    func loadSettings_corruptValue_keepsCurrentCalendar() async throws {
        let f = Fixture()
        try await f.settings.set("{not json", for: SettingKeys.workCalendar)
        await f.environment.loadSettings()
        #expect(f.environment.workCalendar.startHour == 9)
        #expect(f.environment.workCalendar.endHour == 17)
        #expect(f.environment.workCalendar.workWeekdays == Set([2, 3, 4, 5, 6]))
    }

    @Test @MainActor
    func makeProduction_opensMigratedDatabaseAndRoundTrips() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("todayflow-mac-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let environment = try AppEnvironment.makeProduction(
            databaseURL: directory.appendingPathComponent("todayflow.sqlite")
        )
        let item = try await CreateTask(
            repository: environment.workItems,
            calendar: environment.workCalendar
        ).execute(.init(kind: .task, title: "First task"))
        #expect((await environment.workItems.item(item.id))?.title == "First task")
    }
}
