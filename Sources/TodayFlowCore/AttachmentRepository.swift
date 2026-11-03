import Foundation

/// Port for persisting attachments (driver.md §6).
public protocol AttachmentRepository: Sendable {
    /// Attachments belonging to `itemId`.
    func attachments(for itemId: UUIDv7) async -> [Attachment]

    /// Insert or update an attachment (upsert by `id`).
    func save(_ attachment: Attachment) async throws

    /// Hard-delete an attachment.
    func delete(_ id: UUIDv7) async throws
}
