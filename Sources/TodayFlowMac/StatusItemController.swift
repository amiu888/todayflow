#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI
import TodayFlowCore
import TodayFlowDesign
import TodayFlowFeatures

/// Owns the menu-bar item (driver.md FR-40, Phase 3 line 517): the progress
/// ring + remaining count, a transient popover hosting the full Today view,
/// and a right-click menu with the standard window commands.
@MainActor
public final class StatusItemController: NSObject {
    public private(set) var statusItem: NSStatusItem
    public private(set) var popover: NSPopover
    private let environment: AppEnvironment
    private let windowManager: WindowManager
    private let summary: TodaySummaryModel

    public init(
        environment: AppEnvironment,
        windowManager: WindowManager,
        summary: TodaySummaryModel
    ) {
        self.environment = environment
        self.windowManager = windowManager
        self.summary = summary
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()
        configure()
    }

    private func configure() {
        guard let button = statusItem.button else { return }
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.behavior = .transient
        popover.contentSize = DesignTokens.Window.menuBar
        popover.contentViewController = NSHostingController(
            rootView: TodayView(
                repository: environment.workItems,
                linkRepository: environment.links,
                attachmentRepository: environment.attachments,
                settingRepository: environment.settings,
                calendar: environment.workCalendar,
                onOpenTask: { [weak windowManager] id in windowManager?.show(.detail(id)) },
                onDrop: { [weak windowManager] providers, itemId in
                    windowManager?.handleDrop(providers, onto: itemId) ?? false
                }
            )
        )

        installDropTarget(on: button)
        apply(progress: summary.progress)
    }

    /// FR-01: the menu-bar icon accepts drops. The transparent overlay forwards
    /// clicks to this controller and turns drops into a capture sheet.
    private func installDropTarget(on button: NSStatusBarButton) {
        let dropView = StatusDropView()
        dropView.translatesAutoresizingMaskIntoConstraints = false
        dropView.canDrop = { DroppedObjectLoader.canRead($0) }
        dropView.onDrop = { [weak self] pasteboard in
            guard let self else { return false }
            let objects = DroppedObjectLoader.objects(from: pasteboard)
            guard !objects.isEmpty else { return false }
            self.windowManager.receiveDrop(objects)
            return true
        }
        dropView.onClick = { [weak self] isRightClick in
            self?.handleStatusClick(isRightClick: isRightClick)
        }
        dropView.registerForDraggedTypes(DroppedObjectLoader.pasteboardTypes)
        button.addSubview(dropView)
        NSLayoutConstraint.activate([
            dropView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            dropView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            dropView.topAnchor.constraint(equalTo: button.topAnchor),
            dropView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
    }

    /// FR-40: remaining count + mini progress ring.
    public func apply(progress: TodayQuery.Progress) {
        guard let button = statusItem.button else { return }
        button.image = StatusItemIcon.image(fraction: progress.fraction)
        button.title = progress.isCleared ? " ✓" : " \(progress.remaining)"
        let ring = ProgressRingModel(done: progress.done, total: progress.total)
        button.toolTip = "\(ring.doneLabel) · \(ring.remainingLabel)"
    }

    @objc private func handleClick() {
        handleStatusClick(isRightClick: NSApp.currentEvent?.type == .rightMouseUp)
    }

    /// Shared by the status button action and the drop overlay.
    func handleStatusClick(isRightClick: Bool) {
        if isRightClick {
            showMenu()
        } else {
            toggle()
        }
    }

    /// Left click: open/close the popover.
    public func toggle() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// The right-click menu: the standard window commands + quit.
    public var menu: NSMenu {
        let menu = NSMenu()
        menu.addItem(item("New Task…", #selector(newTask)))
        menu.addItem(.separator())
        menu.addItem(item("Open Today", #selector(openPanel)))
        menu.addItem(item("Slim bar", #selector(toggleSlimBar)))
        menu.addItem(item("Hierarchy", #selector(openHierarchy)))
        menu.addItem(item("Settings", #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(item("Quit TodayFlow", #selector(quit)))
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        return menuItem
    }

    @objc private func newTask() { windowManager.showCapture() }

    @objc private func openPanel() { windowManager.show(.panel) }

    @objc private func toggleSlimBar() {
        if windowManager.isOpen(.slimBar) {
            windowManager.close(.slimBar)
        } else {
            windowManager.show(.slimBar)
        }
    }

    @objc private func openHierarchy() { windowManager.show(.hierarchy) }

    @objc private func openSettings() { windowManager.show(.settings) }

    @objc private func quit() { NSApp.terminate(nil) }
}
#endif
