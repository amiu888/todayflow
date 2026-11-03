import Foundation

/// In-memory `AttachmentRepository` (driver.md §5: every port has an in-memory adapter).
public actor InMemoryAttachmentRepository: AttachmentRepository {
    private var attachments: [UUIDv7: Attachment] = [:]

    public init() {}

    // MARK: AttachmentRepository

    public func attachments(for itemId: UUIDv7) async -> [Attachment] {
        attachments.values.filter { $0.itemId == itemId }
    }

    public func save(_ attachment: Attachment) async throws {
        attachments[attachment.id] = attachment
    }

    public func delete(_ id: UUIDv7) async throws {
        attachments.removeValue(forKey: id)
    }

    // MARK: Test helpers

    public func seed(_ attachment: Attachment) {
        attachments[attachment.id] = attachment
    }

    public var all: [Attachment] { Array(attachments.values) }
}
