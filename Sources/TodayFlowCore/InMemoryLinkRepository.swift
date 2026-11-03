import Foundation

/// In-memory `LinkRepository` (driver.md §5: every port has an in-memory adapter).
public actor InMemoryLinkRepository: LinkRepository {
    private var links: [UUIDv7: ItemLink] = [:]

    public init() {}

    // MARK: LinkRepository

    public func links(from id: UUIDv7) async -> [ItemLink] {
        links.values.filter { $0.fromId == id }
    }

    public func links(to id: UUIDv7) async -> [ItemLink] {
        links.values.filter { $0.toId == id }
    }

    public func allLinks() async -> [ItemLink] {
        Array(links.values)
    }

    public func save(_ link: ItemLink) async throws {
        links[link.id] = link
    }

    public func delete(_ id: UUIDv7) async throws {
        links.removeValue(forKey: id)
    }

    // MARK: Test helpers

    public func seed(_ link: ItemLink) {
        links[link.id] = link
    }
}
