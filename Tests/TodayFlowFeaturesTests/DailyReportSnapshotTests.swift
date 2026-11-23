#if canImport(AppKit)
import AppKit
import SwiftUI
import Testing
@testable import TodayFlowFeatures
import TodayFlowCore

/// `TODAYFLOW_WRITE_REPORT_IMAGES=<folder> swift test --filter DailyReportSnapshot`
@MainActor
struct DailyReportSnapshotTests {
    @Test func writeImages() async throws {
        guard let folder = ProcessInfo.processInfo.environment["TODAYFLOW_WRITE_REPORT_IMAGES"] else { return }
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repo = InMemoryWorkItemRepository()
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func at(_ h: Int, _ d: Int = 0) -> Date { cal.date(byAdding: .hour, value: h + d * 24, to: today)! }
        let project = WorkItem(kind: .project, title: "Java removal", createdAt: at(-48), updatedAt: at(-48))
        try await repo.save(project)
        let items: [WorkItem] = [
            WorkItem(title: "CHG0012345 - remove Java from app servers", parentId: project.id,
                     descriptionMd: DescriptionLog.adding("Change closed after smoke tests passed.", at: at(11), to: "", createdAt: at(-48)),
                     status: .done, priority: .urgent, startAt: at(9), endAt: at(17), estimatedMinutes: 120,
                     completedAt: at(11), createdAt: at(-48), updatedAt: at(11)),
            WorkItem(title: "Patch db-server-01", status: .done, priority: .high, startAt: at(9), endAt: at(17),
                     estimatedMinutes: 60, completedAt: at(14), createdAt: at(-24), updatedAt: at(14)),
            WorkItem(title: "Reply to Alex about licences",
                     descriptionMd: DescriptionLog.adding("Sent the draft; waiting on the renewal numbers.", at: at(15), to: "", createdAt: at(-24)),
                     status: .inProgress, startAt: at(9), endAt: at(17, 2), createdAt: at(-24), updatedAt: at(15)),
            WorkItem(title: "Vendor access for nas.local", status: .blocked, priority: .high,
                     startAt: at(-24), endAt: at(-7), createdAt: at(-30), updatedAt: at(-24)),
            WorkItem(title: "Update the backup runbook", startAt: at(9), endAt: at(12), createdAt: at(-24), updatedAt: at(-24)),
            WorkItem(title: "Plan Q2 capacity review", priority: .high, startAt: at(9, 1), endAt: at(17, 1),
                     createdAt: at(-24), updatedAt: at(-24)),
        ]
        for item in items { try await repo.save(item) }
        let defaults = UserDefaults(suiteName: "dailyReportSnapshot")!
        defaults.removePersistentDomain(forName: "dailyReportSnapshot")
        let model = DailyReportModel(repository: repo, clock: { cal.date(byAdding: .hour, value: 17, to: today)! }, defaults: defaults)
        model.author = "Alex Morgan, Infrastructure"
        await model.load()
        for (name, scheme, appearance) in [("report-dark", ColorScheme.dark, NSAppearance.Name.darkAqua), ("report-light", .light, .aqua)] {
            let host = NSHostingView(rootView: DailyReportView(model: model).environment(\.colorScheme, scheme))
            host.appearance = NSAppearance(named: appearance)
            host.frame = NSRect(x: 0, y: 0, width: 600, height: 680)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(400))
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            try #require(rep.representation(using: .png, properties: [:])).write(to: root.appendingPathComponent("\(name).png"))
        }
    }
}
#endif
