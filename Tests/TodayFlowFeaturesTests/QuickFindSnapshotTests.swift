#if canImport(AppKit)
import AppKit
import SwiftUI
import Testing
@testable import TodayFlowFeatures
import TodayFlowCore
import TodayFlowDesign

/// `TODAYFLOW_WRITE_FIND_IMAGES=<folder> swift test --filter QuickFindSnapshot`
@MainActor
struct QuickFindSnapshotTests {
    @Test func writeImages() async throws {
        guard let folder = ProcessInfo.processInfo.environment["TODAYFLOW_WRITE_FIND_IMAGES"] else { return }
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let now = Date()
        let repository = InMemoryWorkItemRepository()
        let project = WorkItem(kind: .project, title: "Server clean-up", color: "#5B8DEF")
        await repository.seed(project)
        let items = [
            WorkItem(title: "CHG0012345 - remove Java", parentId: project.id,
                     descriptionMd: "The database client still uses Java on db-server-01.",
                     endAt: now.addingTimeInterval(3_600), tags: ["CHG0012345", "db-server-01"]),
            WorkItem(title: "Patch web-server-01a", parentId: project.id, endAt: now.addingTimeInterval(-7_200), tags: ["web-server-01a"]),
            WorkItem(title: "Reply to Alex about licences", descriptionMd: "Alex asked whether Java licences renew in March.",
                     endAt: now.addingTimeInterval(3 * 86_400)),
            WorkItem(title: "Old Java upgrade", status: .done, endAt: now.addingTimeInterval(-20 * 86_400),
                     completedAt: now.addingTimeInterval(-20 * 86_400)),
        ]
        for item in items { await repository.seed(item) }
        let recent = [items[2].id, items[0].id]
        let model = QuickFindModel(
            repository: repository, linkRepository: InMemoryLinkRepository(),
            attachmentRepository: InMemoryAttachmentRepository(), recent: { recent }
        )
        model.onAsk = { _ in }
        await model.load()

        func render(_ name: String, _ scheme: ColorScheme) async throws {
            let size = CGSize(width: 640, height: 460)
            let host = NSHostingView(rootView: QuickFindView(model: model).environment(\.colorScheme, scheme))
            host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            try #require(rep.representation(using: .png, properties: [:]))
                .write(to: root.appendingPathComponent("find-\(name).png"))
        }
        try await render("empty", .dark)
        model.text = "java"
        try await render("java", .dark)
        try await render("java-light", .light)
        model.text = "overdue #web"
        try await render("filters", .dark)
    }
}
#endif
