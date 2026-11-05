#if canImport(AppKit)
import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
import TodayFlowCore
import TodayFlowFeatures

@MainActor
struct DragPayloadTests {
    @Test func providerRoundTripsItemAndSourceTray() async throws {
        let item = UUIDv7.new()
        let tray = UUIDv7.new()
        let provider = WorkItemDragPayload.itemProvider(for: item, sourceTray: tray)
        let raw = try #require(
            try await provider.loadItem(
                forTypeIdentifier: UTType.todayFlowWorkItem.identifier,
                options: nil
            ) as? String
        )
        let decoded = try #require(WorkItemDragPayload.decode(raw))

        #expect(decoded.itemId == item)
        #expect(decoded.sourceTray == tray)
    }

    @Test func providerWithoutTrayIsAnAddNotAMove() async throws {
        let item = UUIDv7.new()
        let provider = WorkItemDragPayload.itemProvider(for: item)
        let raw = try #require(
            try await provider.loadItem(
                forTypeIdentifier: UTType.todayFlowWorkItem.identifier,
                options: nil
            ) as? String
        )
        let decoded = try #require(WorkItemDragPayload.decode(raw))

        #expect(decoded.itemId == item)
        #expect(decoded.sourceTray == nil)
    }
}
#endif

@MainActor
struct DragPayloadLoadingTests {
    @Test func loadsStringProvider() async {
        let item = UUIDv7.new()
        let tray = UUIDv7.new()
        let box = WorkItemDragPayload.ProviderBox(
            WorkItemDragPayload.itemProvider(for: item, sourceTray: tray)
        )
        let payload = await WorkItemDragPayload.load(from: box.provider)

        #expect(payload?.itemId == item)
        #expect(payload?.sourceTrayId == tray)
    }

    @Test func loadsCodableProvider() async throws {
        let item = UUIDv7.new()
        let tray = UUIDv7.new()
        let expected = WorkItemDragPayload(itemId: item, sourceTrayId: tray)
        let data = try JSONEncoder().encode(expected)
        let box = WorkItemDragPayload.ProviderBox(NSItemProvider(
            item: data as NSData,
            typeIdentifier: UTType.todayFlowWorkItem.identifier
        ))

        let payload = await WorkItemDragPayload.load(from: box.provider)

        #expect(payload?.itemId == item)
        #expect(payload?.sourceTrayId == tray)
    }

    @Test func rejectsUnreadablePayload() async throws {
        let box = WorkItemDragPayload.ProviderBox(NSItemProvider(
            item: Data("not a payload".utf8) as NSData,
            typeIdentifier: UTType.todayFlowWorkItem.identifier
        ))

        let payload = await WorkItemDragPayload.load(from: box.provider)

        #expect(payload == nil)
    }
}

@MainActor
struct DragPasteboardSnapshotTests {
    private func pasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("todayflow-tests-\(UUID().uuidString)"))
    }

    private var dragType: NSPasteboard.PasteboardType {
        NSPasteboard.PasteboardType(UTType.todayFlowWorkItem.identifier)
    }

    @Test func snapshotsStringPayloads() {
        let item = UUIDv7.new()
        let tray = UUIDv7.new()
        let board = pasteboard()
        board.clearContents()
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(
            "\(item.uuid.uuidString)|\(tray.uuid.uuidString)",
            forType: dragType
        )
        board.writeObjects([pasteboardItem])

        let payloads = WorkItemDragPayload.loadAll(from: board)

        #expect(payloads.count == 1)
        #expect(payloads.first?.itemId == item)
        #expect(payloads.first?.sourceTrayId == tray)
    }

    @Test func snapshotsMultiplePayloads() {
        let board = pasteboard()
        board.clearContents()
        let items = (0..<3).map { _ -> NSPasteboardItem in
            let item = NSPasteboardItem()
            item.setString(
                UUIDv7.new().uuid.uuidString,
                forType: dragType
            )
            return item
        }
        board.writeObjects(items)

        let payloads = WorkItemDragPayload.loadAll(from: board)

        #expect(payloads.count == 3)
        #expect(payloads.allSatisfy { $0.sourceTrayId == nil })
    }

    @Test func snapshotsCodablePayloads() throws {
        let item = UUIDv7.new()
        let tray = UUIDv7.new()
        let board = pasteboard()
        board.clearContents()
        let data = try JSONEncoder().encode(
            WorkItemDragPayload(itemId: item, sourceTrayId: tray)
        )
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(data, forType: dragType)
        board.writeObjects([pasteboardItem])

        let payloads = WorkItemDragPayload.loadAll(from: board)

        #expect(payloads.first?.itemId == item)
        #expect(payloads.first?.sourceTrayId == tray)
    }
}
