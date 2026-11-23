#if canImport(AppKit)
import AppKit
import SwiftUI
import Testing
@testable import TodayFlowFeatures
import TodayFlowCore

/// `TODAYFLOW_WRITE_SWITCHER_IMAGES=<folder> swift test --filter TaskWindowsSnapshot`
@MainActor
struct TaskWindowsSnapshotTests {
    @Test func writeImages() async throws {
        guard let folder = ProcessInfo.processInfo.environment["TODAYFLOW_WRITE_SWITCHER_IMAGES"] else { return }
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let now = Date()
        let model = TaskWindowsModel()
        model.layout = .stack
        model.order = .priority
        model.entries = TaskWindowStack.sorted([
            TaskWindowEntry(id: .new(), title: "CHG0012345 - remove Java", priority: .urgent, dueAt: now.addingTimeInterval(3_600), openedAt: now),
            TaskWindowEntry(id: .new(), title: "Patch web-server-01a", priority: .high, dueAt: now.addingTimeInterval(-7_200), openedAt: now),
            TaskWindowEntry(id: .new(), title: "Reply to Alex about licences", priority: .normal, dueAt: now.addingTimeInterval(3 * 86_400), openedAt: now),
            TaskWindowEntry(id: .new(), title: "Book dentist", priority: .low, dueAt: now.addingTimeInterval(9 * 86_400), openedAt: now),
        ], by: .priority)
        model.activeId = model.entries.first?.id
        let host = NSHostingView(rootView: TaskWindowsView(model: model).environment(\.colorScheme, .dark))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = NSRect(x: 0, y: 0, width: 420, height: 400)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: root.appendingPathComponent("switcher.png"))
    }
}
#endif
