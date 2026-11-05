#if canImport(AppKit)
import AppKit
import SwiftUI
import Testing
import TodayFlowCore
@testable import TodayFlowFeatures

@MainActor
struct TrayDropAreaTests {
    private final class MockDraggingInfo: NSObject, NSDraggingInfo {
        let draggingPasteboard: NSPasteboard

        @MainActor
        init(pasteboard: NSPasteboard) {
            self.draggingPasteboard = pasteboard
        }

        var draggingDestinationWindow: NSWindow?
        var draggingSourceOperationMask: NSDragOperation = .copy
        var draggingLocation: NSPoint = .zero
        var draggedImageLocation: NSPoint = .zero
        var draggedImage: NSImage?
        var draggingSource: Any?
        var draggingSequenceNumber: Int = 1
        var draggingFormation: NSDraggingFormation = .default
        var animatesToDestination = false
        var numberOfValidItemsForDrop = 1

        func slideDraggedImage(to screenPoint: NSPoint) {}
        func enumerateDraggingItems(
            options enumOpts: NSDraggingItemEnumerationOptions,
            for view: NSView?,
            classes classArray: [AnyClass],
            searchOptions: [NSPasteboard.ReadingOptionKey: Any],
            using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
        ) {}
        var springLoadingHighlight: NSSpringLoadingHighlight = .none
        func resetSpringLoading() {}
    }

    @Test func appKitDestinationDeliversEagerPayload() {
        let item = UUIDv7.new()
        let tray = UUIDv7.new()
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("todayflow-drop-\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        pasteboard.writeObjects([
            WorkItemDragPayload.pasteboardItem(for: item, sourceTray: tray)
        ])

        let view = TrayDropArea<Text>.DropView(rootView: Text("tray"))
        var received: [WorkItemDragPayload] = []
        view.onDrop = { payloads in
            received = payloads
            return true
        }
        let info = MockDraggingInfo(pasteboard: pasteboard)

        #expect(view.draggingEntered(info) == .copy)
        #expect(view.performDragOperation(info))
        #expect(received.count == 1)
        #expect(received.first?.itemId == item)
        #expect(received.first?.sourceTrayId == tray)
    }

    @Test func appKitDestinationRejectsUnrelatedText() {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("todayflow-drop-\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        pasteboard.setString("not a task", forType: .string)

        let view = TrayDropArea<Text>.DropView(rootView: Text("tray"))
        let info = MockDraggingInfo(pasteboard: pasteboard)

        #expect(view.draggingEntered(info) == [])
        #expect(view.performDragOperation(info) == false)
    }

}
#endif
