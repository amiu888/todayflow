import SwiftUI
import UniformTypeIdentifiers
import TodayFlowCore

/// The app's exported UTType for dragging a work item between lists.
///
/// `UTType(exportedAs:)` works for in-app drag & drop without an Info.plist
/// declaration; adding `UTExportedTypeDeclarations` to the app target's
/// Info.plist is a 6.6 refinement (the package currently has no resources).
public extension UTType {
    static let todayFlowWorkItem = UTType(exportedAs: "com.todayflow.work-item")
}

/// The drag payload for a work item (driver.md FR-12 / FR-16: drag to reorder,
/// drag to reparent, drag to top level).
///
/// Shared by the Today list and the hierarchy — one payload type, one UTType,
/// so the two views can exchange drags and each decides what a drop means.
public struct WorkItemDragPayload: Codable, Transferable {
    public let itemId: UUIDv7

    public init(itemId: UUIDv7) {
        self.itemId = itemId
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .todayFlowWorkItem)
    }
}
