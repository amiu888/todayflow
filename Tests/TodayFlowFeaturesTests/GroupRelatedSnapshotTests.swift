#if canImport(AppKit)
import AppKit
import SwiftUI
import Testing
@testable import TodayFlowFeatures
import TodayFlowCore
import TodayFlowDesign

/// `TODAYFLOW_WRITE_GROUP_IMAGES=<folder> swift test --filter GroupRelatedSnapshot`
@MainActor
struct GroupRelatedSnapshotTests {
    @Test func writeImages() async throws {
        guard let folder = ProcessInfo.processInfo.environment["TODAYFLOW_WRITE_GROUP_IMAGES"] else { return }
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repository = InMemoryWorkItemRepository()
        let other = WorkItem(kind: .project, title: "Website")
        let target = WorkItem(title: "CHG0012345 - remove Java", tags: ["db-server-01"])
        let items = [
            other, target,
            WorkItem(title: "Rollback plan", descriptionMd: "for CHG0012345"),
            WorkItem(title: "Test CHG0012345 in staging", status: .done, completedAt: .now),
            WorkItem(title: "Disk space alert", tags: ["db-server-01"]),
            WorkItem(title: "Update db-server-01 notes", parentId: other.id, tags: ["db-server-01"]),
        ]
        for item in items { await repository.seed(item) }
        let model = GroupRelatedModel(targetId: target.id, repository: repository, attachmentRepository: InMemoryAttachmentRepository())
        await model.load()
        let host = NSHostingView(rootView: GroupRelatedView(model: model).environment(\.colorScheme, .dark))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = NSRect(x: 0, y: 0, width: 560, height: 520)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: root.appendingPathComponent("group.png"))
    }
}
#endif
