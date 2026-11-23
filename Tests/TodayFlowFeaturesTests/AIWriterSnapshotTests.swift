#if canImport(AppKit)
import AppKit
import SwiftUI
import Testing
@testable import TodayFlowFeatures
import TodayFlowCore
import TodayFlowDesign

/// Renders the AI Writer before and after a request, wide and narrow.
/// `TODAYFLOW_WRITE_WRITER_IMAGES=<folder> swift test --filter AIWriterSnapshot`
@MainActor
struct AIWriterSnapshotTests {
    private struct Canned: TextRewriting {
        func rewrite(_ original: String, conversation: [RewriteTurn]) async throws -> RewriteReply {
            RewriteReply(
                text: "Hi Alex,\n\nCould you please confirm whether the database client still needs Java? We would like to remove it from db-server-01 by Friday.\n\nThank you.",
                note: "Made it more formal and added a clear ask and deadline."
            )
        }
    }

    @Test func writeImages() async throws {
        guard let folder = ProcessInfo.processInfo.environment["TODAYFLOW_WRITE_WRITER_IMAGES"] else { return }
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = "hey alex does the db client still need java? want to remove it from db-server-01 friday"

        func render(_ model: AIWriterModel, _ size: CGSize, _ scheme: ColorScheme, _ name: String) async throws {
            let host = NSHostingView(rootView: AIWriterView(model: model)
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, scheme))
            host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            try #require(rep.representation(using: .png, properties: [:]))
                .write(to: root.appendingPathComponent("writer-\(name).png"))
        }

        let fresh = AIWriterModel(original: original, fieldName: "Note")
        fresh.rewriter = Canned()
        fresh.isResolvingAI = false
        try await render(fresh, CGSize(width: 820, height: 620), .dark, "start-dark")

        let answered = AIWriterModel(original: original, fieldName: "Note")
        answered.rewriter = Canned()
        answered.isResolvingAI = false
        await answered.send(.formal)
        try await render(answered, CGSize(width: 820, height: 620), .dark, "answered-dark")
        try await render(answered, CGSize(width: 820, height: 620), .light, "answered-light")
        try await render(answered, CGSize(width: 560, height: 560), .dark, "answered-narrow")

        let off = AIWriterModel(original: original, fieldName: "Note")
        off.isResolvingAI = false
        off.onOpenSettings = {}
        try await render(off, CGSize(width: 820, height: 620), .dark, "ai-off")
    }
}
#endif
