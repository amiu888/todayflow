#if canImport(AppKit)
import AppKit
import SwiftUI
import Testing
@testable import TodayFlowFeatures
import TodayFlowCore

/// Renders the side-by-side contact compare for a visual check.
/// `TODAYFLOW_WRITE_CONTACT_IMAGES=<folder> swift test --filter ContactCompareSnapshot`
@MainActor
struct ContactCompareSnapshotTests {
    @Test func writeImages() async throws {
        guard let folder = ProcessInfo.processInfo.environment["TODAYFLOW_WRITE_CONTACT_IMAGES"] else { return }
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let existing = Contact(
            firstName: "Jane", lastName: "Smith", company: "Acme", jobTitle: "",
            emails: ["jane@acme.com"], phones: ["+1 555 0100"], notes: "Met at the Q3 review.", source: "macos"
        )
        let dropped = Contact(
            firstName: "Jane", lastName: "Smith-Lee", company: "Acme Corp", jobTitle: "Head of IT",
            emails: ["jane@acme.com", "jane.lee@acme.com"], phones: ["+1 555 0199"], source: "outlook"
        )
        for scheme in [ColorScheme.light, .dark] {
            let view = ContactCompareView(
                existing: existing, dropped: dropped, reason: "Same email: jane@acme.com",
                progress: "1 of 2", allowsUseExisting: true, onChoose: { _ in }, onCancel: {}
            )
            .frame(width: 660, height: 560)
            .environment(\.colorScheme, scheme)
            let host = NSHostingView(rootView: view)
            host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            host.frame = NSRect(x: 0, y: 0, width: 660, height: 560)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let data = try #require(rep.representation(using: .png, properties: [:]))
            try data.write(to: root.appendingPathComponent("compare-\(scheme == .dark ? "dark" : "light").png"))
        }
    }
}
#endif
