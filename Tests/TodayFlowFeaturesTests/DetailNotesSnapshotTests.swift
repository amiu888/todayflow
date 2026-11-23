#if canImport(AppKit)
import AppKit
import SwiftUI
import Testing
@testable import TodayFlowFeatures
import TodayFlowCore
import TodayFlowDesign

/// Renders a task with many tags and time-stamped notes.
/// `TODAYFLOW_WRITE_NOTES_IMAGES=<folder> swift test --filter DetailNotesSnapshot`
@MainActor
struct DetailNotesSnapshotTests {
    @Test func writeImages() async throws {
        guard let folder = ProcessInfo.processInfo.environment["TODAYFLOW_WRITE_NOTES_IMAGES"] else { return }
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let now = Date()
        var description = "Today's conversation with Alex about removing Java from the app servers."
        description = DescriptionLog.adding("Java can't simply be removed: the database client uses it. Checking with the Compute team.", at: now.addingTimeInterval(-3 * 3600), to: description, createdAt: now.addingTimeInterval(-86400))
        description = DescriptionLog.adding("Compute team says the client can go. Raise **CTASK0012399** again for Thursday.", at: now.addingTimeInterval(-600), to: description, createdAt: now.addingTimeInterval(-86400))
        let items = InMemoryWorkItemRepository()
        let item = WorkItem(
            title: "CHG0012345 - remove Java", descriptionMd: description, priority: .high,
            startAt: now, endAt: now.addingTimeInterval(8 * 3600),
            tags: ["CHG0012345", "Alex-Morgan", "billing", "Sam", "db-server-01", "db-server-02", "web-server-01a", "web-server-01b", "scheduler", "sso-agent"],
            createdAt: now.addingTimeInterval(-86400)
        )
        await items.seed(item)
        let model = DetailViewModel(
            itemId: item.id, repository: items, linkRepository: InMemoryLinkRepository(),
            attachmentRepository: InMemoryAttachmentRepository(), contactRepository: InMemoryContactRepository()
        )
        await model.load()
        // The smallest, the usual and a wide task window.
        let shots: [(ColorScheme, CGFloat)] = [(.dark, 720), (.light, 720), (.dark, 480), (.dark, 1300)]
        for (scheme, width) in shots {
            let host = NSHostingView(rootView: DetailView(model: model, onOpenInObsidian: { _ in })
                .frame(width: width, height: 1100)
                .environment(\.colorScheme, scheme)
                .background(DesignTokens.Palette.background))
            host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            host.frame = NSRect(x: 0, y: 0, width: width, height: 1100)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            try #require(rep.representation(using: .png, properties: [:]))
                .write(to: root.appendingPathComponent("detail-\(scheme == .dark ? "dark" : "light")-\(Int(width)).png"))
        }
    }
}
#endif
