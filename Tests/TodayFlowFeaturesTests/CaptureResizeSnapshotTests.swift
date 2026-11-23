#if canImport(AppKit)
import AppKit
import SwiftUI
import Testing
@testable import TodayFlowFeatures
import TodayFlowCore
import TodayFlowDesign

/// Renders the New Task panel at its smallest, usual and a large size.
/// `TODAYFLOW_WRITE_CAPTURE_IMAGES=<folder> swift test --filter CaptureResizeSnapshot`
@MainActor
struct CaptureResizeSnapshotTests {
    @Test func writeImages() async throws {
        guard let folder = ProcessInfo.processInfo.environment["TODAYFLOW_WRITE_CAPTURE_IMAGES"] else { return }
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let now = Date()
        let draft = CaptureDraft(
            title: "CHG0012345 - patch db-server-01",
            descriptionMd: "Alex asked to patch the database server before Friday.",
            startAt: now, endAt: now.addingTimeInterval(4 * 3600)
        )
        let sizes: [CGSize] = [
            DesignTokens.Window.captureMinimum, DesignTokens.Window.capture, CGSize(width: 640, height: 760),
        ]
        for size in sizes {
            let host = NSHostingView(rootView: CaptureSheetView(
                draft: .constant(draft), onSave: {}, onCancel: {}, onRemoveObject: { _ in }
            )
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark))
            host.appearance = NSAppearance(named: .darkAqua)
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            try #require(rep.representation(using: .png, properties: [:]))
                .write(to: root.appendingPathComponent("capture-\(Int(size.width))x\(Int(size.height)).png"))
        }
    }
}
#endif
