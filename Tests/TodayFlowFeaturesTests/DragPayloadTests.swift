#if canImport(AppKit)
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
