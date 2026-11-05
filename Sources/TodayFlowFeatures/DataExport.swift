import Foundation
import TodayFlowCore

/// JSON and CSV export of the task store (driver.md NFR-09: "export to
/// JSON/CSV"). Pure and testable; the Mac layer owns the save panel.
public struct DataExport: Sendable {
    public enum Format: String, CaseIterable, Identifiable, Sendable {
        case json
        case csv

        public var id: String { rawValue }
        public var fileExtension: String { rawValue }
        public var label: String { self == .json ? "JSON" : "CSV" }
    }

    public init() {}

    public func data(for items: [WorkItem], format: Format) throws -> Data {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(items)
        case .csv:
            return Data(csv(for: items).utf8)
        }
    }

    private func csv(for items: [WorkItem]) -> String {
        let formatter = ISO8601DateFormatter()
        let header = [
            "id", "kind", "title", "parent_id", "status", "priority",
            "start_at", "end_at", "completed_at", "display_order", "tags",
            "description",
        ]
        var rows = [header.map(escape).joined(separator: ",")]

        for item in items.sorted(by: sortByCreatedAt) {
            let row = [
                item.id.uuid.uuidString,
                item.kind.rawValue,
                item.title,
                item.parentId?.uuid.uuidString ?? "",
                item.status.rawValue,
                "P\(item.priority.rawValue)",
                formatter.string(from: item.startAt),
                formatter.string(from: item.endAt),
                item.completedAt.map(formatter.string(from:)) ?? "",
                item.displayOrder,
                item.tags.joined(separator: "; "),
                item.descriptionMd,
            ]
            rows.append(row.map(escape).joined(separator: ","))
        }

        return rows.joined(separator: "\r\n") + "\r\n"
    }

    private func sortByCreatedAt(_ left: WorkItem, _ right: WorkItem) -> Bool {
        if left.createdAt != right.createdAt { return left.createdAt < right.createdAt }
        return left.id < right.id
    }

    /// RFC 4180 field escaping: quote when the value contains a comma, quote,
    /// CR, or LF; double embedded quotes.
    private func escape(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
        else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
