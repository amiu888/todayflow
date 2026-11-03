import Foundation

/// Port for persisting item-to-item links (driver.md §6).
public protocol LinkRepository: Sendable {
    /// Links whose `fromId` is `id` (things `id` blocks / relates to).
    func links(from id: UUIDv7) async -> [ItemLink]

    /// Links whose `toId` is `id` (things that block / relate to `id`).
    func links(to id: UUIDv7) async -> [ItemLink]

    /// All links.
    func allLinks() async -> [ItemLink]

    /// Insert or update a link (upsert by `id`).
    func save(_ link: ItemLink) async throws

    /// Hard-delete a link.
    func delete(_ id: UUIDv7) async throws
}
