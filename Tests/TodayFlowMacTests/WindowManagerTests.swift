#if canImport(AppKit)
import AppKit
import Foundation
import Testing
import TodayFlowCore
import TodayFlowDesign
import TodayFlowMac
import TodayFlowRecognition

@MainActor
private func makeEnvironment() -> AppEnvironment {
    AppEnvironment(
        workItems: InMemoryWorkItemRepository(),
        links: InMemoryLinkRepository(),
        attachments: InMemoryAttachmentRepository(),
        settings: InMemorySettingRepository(),
        keychain: InMemoryKeychainStore(),
        pipeline: .standard
    )
}

struct WindowManagerTests {
    @Test @MainActor
    func show_createsWindowAtCatalogSize() {
        let manager = WindowManager(environment: makeEnvironment())
        #expect(!manager.isOpen(.hierarchy))
        #expect(manager.openCount == 0)
        manager.show(.hierarchy)
        #expect(manager.isOpen(.hierarchy))
        #expect(manager.openCount == 1)
        #expect(manager.window(for: .hierarchy)?.title == "Hierarchy")
        #expect(manager.window(for: .hierarchy)?.contentView?.frame.size == DesignTokens.Window.hierarchy)
    }

    @Test @MainActor
    func panelRespectsTheDesktopAnchor() throws {
        let manager = WindowManager(environment: makeEnvironment())
        manager.show(.panel)
        let panel = try #require(manager.window(for: .panel))
        #expect(!panel.collectionBehavior.contains(.canJoinAllSpaces))

        manager.showOnAllDesktops = true
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))

        manager.showOnAllDesktops = false
        #expect(!panel.collectionBehavior.contains(.canJoinAllSpaces))
    }

    @Test @MainActor
    func contacts_opensBesideThePanel() {
        let manager = WindowManager(environment: makeEnvironment())
        manager.show(.panel)
        let panel = manager.window(for: .panel)!
        panel.setFrame(NSRect(x: 100, y: 100, width: 360, height: 640), display: false)

        manager.show(.contacts)
        let contacts = manager.window(for: .contacts)!

        #expect(!contacts.frame.intersects(panel.frame))
        #expect(contacts.frame.minX >= panel.frame.minX)
        #expect(!contacts.isMovableByWindowBackground)
    }

    @Test @MainActor
    func contacts_canShrinkToTheResponsiveMinimum() {
        let manager = WindowManager(environment: makeEnvironment())
        manager.show(.contacts)
        let contacts = manager.window(for: .contacts)!
        #expect(contacts.contentMinSize == DesignTokens.Window.contactsMinimum)
        #expect(DesignTokens.Window.contactsMinimum.width <= 600)
    }

    @Test @MainActor
    func show_twice_reusesTheSameWindow() {
        let manager = WindowManager(environment: makeEnvironment())
        manager.show(.panel)
        let first = manager.window(for: .panel)
        manager.show(.panel)
        let second = manager.window(for: .panel)
        #expect(first === second)
        #expect(manager.openCount == 1)
    }

    @Test @MainActor
    func close_removesWindow() {
        let manager = WindowManager(environment: makeEnvironment())
        manager.show(.settings)
        #expect(manager.isOpen(.settings))
        manager.close(.settings)
        #expect(!manager.isOpen(.settings))
        #expect(manager.openCount == 0)
    }

    @Test @MainActor
    func closeAll_closesEveryOpenWindow() {
        let manager = WindowManager(environment: makeEnvironment())
        manager.show(.panel)
        manager.show(.hierarchy)
        manager.show(.settings)
        #expect(manager.openCount == 3)
        manager.closeAll()
        #expect(manager.openCount == 0)
    }

    @Test @MainActor
    func panelWindowHasMinimumSizeFromDesignTokens() {
        let manager = WindowManager(environment: makeEnvironment())
        manager.show(.panel)
        #expect(manager.window(for: .panel)?.contentMinSize == DesignTokens.Window.panelMinimum)
    }

    @Test @MainActor
    func panelWindowIsFloatingPanel() {
        let manager = WindowManager(environment: makeEnvironment())
        manager.show(.panel)
        let window = manager.window(for: .panel)
        #expect(window is PanelWindow)
        #expect((window as? PanelWindow)?.isFloatingPanel == true)
        #expect(window?.isMovableByWindowBackground == false)
        #expect(window?.level == .floating)
    }

    @Test @MainActor
    func windowsGrowWhenResizedAndStopAtTheirMinimum() throws {
        let manager = WindowManager(environment: makeEnvironment())
        let kinds: [WindowKind] = [
            .hierarchy, .insights, .upcoming, .completed, .calendar, .detail(UUIDv7.new()),
        ]
        for kind in kinds {
            manager.show(kind)
            let window = try #require(manager.window(for: kind))
            #expect(window.styleMask.contains(.resizable), "\(kind)")
            #expect(window.contentMinSize.width > 0, "\(kind) has no minimum")

            window.setContentSize(NSSize(width: 1100, height: 820))
            window.layoutIfNeeded()
            #expect(window.contentView?.frame.size == NSSize(width: 1100, height: 820), "\(kind) did not grow")
            manager.close(kind)
        }
    }

    @Test @MainActor
    func slimBarWindowUsesSlimBarSize() {
        let manager = WindowManager(environment: makeEnvironment())
        manager.show(.slimBar)
        let window = manager.window(for: .slimBar)
        #expect(window is PanelWindow)
        #expect(window?.contentView?.frame.size == DesignTokens.Window.slimBar)
        #expect(window?.contentMaxSize == DesignTokens.Window.slimBar)
    }
}

// MARK: - Drop routing

@Test @MainActor
func handleDrop_pngProviderOpensTheCaptureSheet() async throws {
    let manager = WindowManager(environment: makeEnvironment())

    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("TodayFlowDropRouting-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let image = root.appendingPathComponent("photo.png")
    let png = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!
    try png.write(to: image)

    let provider = try #require(NSItemProvider(contentsOf: image))
    #expect(manager.handleDrop([provider], onto: nil))

    let deadline = ContinuousClock.now + .seconds(2)
    while !manager.isCapturePresenting, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(manager.isCapturePresenting, "a PNG drop must open the quick-add sheet")

    manager.closeAll()
}
#endif

@Test @MainActor
func panelContentViewFitsMinimumWidth() async throws {
    let manager = WindowManager(environment: makeEnvironment())
    manager.show(.panel)
    let window = try #require(manager.window(for: .panel))
    window.setContentSize(NSSize(width: DesignTokens.Window.panelMinimum.width, height: 640))
    try await Task.sleep(for: .milliseconds(150))
    print("PANEL contentFrame=\(window.contentView?.frame ?? .zero) fitting=\(window.contentView?.fittingSize ?? .zero) intrinsic=\(window.contentView?.intrinsicContentSize ?? .zero)")
    #expect(window.contentView?.frame.width == DesignTokens.Window.panelMinimum.width)
}

// MARK: - Task window stack

@MainActor
private func waitUntil(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<100 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(20))
    }
}

struct TaskWindowArrangementTests {
    @Test @MainActor
    func stackSortsByPriorityTitlesWindowsAndShowsEveryTitleBar() async throws {
        let workItems = InMemoryWorkItemRepository()
        let now = Date()
        let low = WorkItem(title: "Low one", priority: .low, endAt: now.addingTimeInterval(7_200))
        let urgent = WorkItem(title: "Urgent one", priority: .urgent, endAt: now.addingTimeInterval(3_600))
        let high = WorkItem(title: "High one", priority: .high, endAt: now.addingTimeInterval(1_800))
        for item in [low, urgent, high] { await workItems.seed(item) }
        let environment = AppEnvironment(
            workItems: workItems,
            links: InMemoryLinkRepository(),
            attachments: InMemoryAttachmentRepository(),
            settings: InMemorySettingRepository(),
            keychain: InMemoryKeychainStore(),
            pipeline: .standard
        )
        let manager = WindowManager(environment: environment)
        let arranger = manager.taskWindows
        let previousLayout = arranger.layout
        let previousOrder = arranger.order
        defer {
            arranger.setLayout(previousLayout)
            arranger.setOrder(previousOrder)
        }
        arranger.setOrder(.priority)
        for item in [low, urgent, high] { manager.show(.detail(item.id)) }
        await waitUntil { arranger.model.entries.count == 3 }

        #expect(arranger.model.entries.map(\.title) == ["Urgent one", "High one", "Low one"])
        let urgentWindow = try #require(manager.window(for: .detail(urgent.id)))
        #expect(urgentWindow.title.hasPrefix("P1 · Due "))
        #expect(urgentWindow.title.hasSuffix(" — Urgent one"))

        arranger.setLayout(.stack)
        let frames = [urgent, high, low].compactMap { manager.window(for: .detail($0.id))?.frame }
        #expect(frames.count == 3)
        // Front (urgent) lowest; each window behind it one title bar higher.
        #expect(frames[0].maxY < frames[1].maxY)
        #expect(frames[1].maxY < frames[2].maxY)
        #expect(Set(frames.map(\.minX)).count == 1)
        manager.closeAll()
    }
}
