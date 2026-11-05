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
