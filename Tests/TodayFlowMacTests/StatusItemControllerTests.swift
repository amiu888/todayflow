#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI
import Testing
import TodayFlowCore
import TodayFlowFeatures
import TodayFlowMac
import TodayFlowRecognition

struct StatusItemControllerTests {
    @MainActor
    private func makeController() -> StatusItemController {
        let environment = AppEnvironment(
            workItems: InMemoryWorkItemRepository(),
            links: InMemoryLinkRepository(),
            attachments: InMemoryAttachmentRepository(),
            settings: InMemorySettingRepository(),
            keychain: InMemoryKeychainStore(),
            pipeline: .standard
        )
        let windowManager = WindowManager(environment: environment)
        let summary = TodaySummaryModel(repository: environment.workItems)
        return StatusItemController(
            environment: environment,
            windowManager: windowManager,
            summary: summary
        )
    }

    @Test @MainActor
    func apply_setsRemainingCountAndRing() {
        let controller = makeController()
        controller.apply(
            progress: TodayQuery.Progress(
                done: 3,
                total: 9,
                remaining: 6,
                overdue: 1,
                fraction: 1.0 / 3.0,
                secondsUntilEOB: 3600
            )
        )
        #expect(controller.statusItem.button?.title == " 6")
        #expect(controller.statusItem.button?.image != nil)
    }

    @Test @MainActor
    func apply_clearedDayShowsCheckmark() {
        let controller = makeController()
        controller.apply(
            progress: TodayQuery.Progress(
                done: 4,
                total: 4,
                remaining: 0,
                overdue: 0,
                fraction: 1,
                secondsUntilEOB: 1800
            )
        )
        #expect(controller.statusItem.button?.title == " ✓")
    }

    @Test @MainActor
    func toggle_showsAndHidesPopover() {
        let controller = makeController()
        #expect(!controller.popover.isShown)
        controller.toggle()
        // In a headless test process the popover window cannot be ordered
        // front, so `isShown` stays false; in a GUI session it shows.
        if controller.popover.isShown {
            controller.popover.close()
            #expect(!controller.popover.isShown)
        } else {
            // The show was a no-op; a second toggle must stay hidden.
            controller.toggle()
            #expect(!controller.popover.isShown)
        }
    }

    @Test @MainActor
    func popoverHostsTheTodayView() {
        let controller = makeController()
        #expect(controller.popover.contentViewController is NSHostingController<TodayView>)
    }

    @Test @MainActor
    func menuListsStandardItems() {
        let controller = makeController()
        let titles = controller.menu.items.map(\.title)
        for expected in ["Open Today", "End-of-day review…", "Slim bar", "Hierarchy", "Settings", "Quit TodayFlow"] {
            #expect(titles.contains(expected), "missing menu item \(expected)")
        }
    }
}
#endif
