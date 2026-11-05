import Foundation
import TodayFlowCore

/// JSON and CSV export of the task store (driver.md NFR-09: "export to
/// JSON/CSV"). Pure and testable; the Mac layer owns the save panel.
public struct DataExport: Sendable {
    public enum Format: String, CaseIterable, Identifiable, Sendable {
        case json
        case csv
        case xlsx

        public var id: String { rawValue }
        public var fileExtension: String { rawValue }
        public var label: String {
            switch self {
            case .json: return "JSON"
            case .csv: return "CSV"
            case .xlsx: return "Excel"
            }
        }
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
        case .xlsx:
            throw ExportError.useWriteForExcel
        }
    }

    public enum ExportError: Error, LocalizedError {
        case useWriteForExcel
        case zipFailed

        public var errorDescription: String? {
            switch self {
            case .useWriteForExcel: return "Excel export must be written to a file."
            case .zipFailed: return "Could not package the Excel workbook."
            }
        }
    }

    /// Writes JSON, CSV, or a real `.xlsx` workbook.
    public func write(items: [WorkItem], format: Format, to url: URL) throws {
        switch format {
        case .json, .csv:
            try data(for: items, format: format).write(to: url, options: .atomic)
        case .xlsx:
            try writeXLSX(items: items, to: url)
        }
    }

    private func csv(for items: [WorkItem]) -> String {
        let formatter = ISO8601DateFormatter()
        let header = [
            "id", "kind", "title", "parent_id", "status", "priority",
            "estimate_min", "start_at", "end_at", "completed_at", "display_order",
            "tags", "description", "summary",
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
                item.estimatedMinutes.map(String.init) ?? "",
                formatter.string(from: item.startAt),
                formatter.string(from: item.endAt),
                item.completedAt.map(formatter.string(from:)) ?? "",
                item.displayOrder,
                item.tags.joined(separator: "; "),
                item.descriptionMd,
                item.summary,
            ]
            rows.append(row.map(escape).joined(separator: ","))
        }

        return rows.joined(separator: "\r\n") + "\r\n"
    }

    // MARK: - XLSX

    private func writeXLSX(items: [WorkItem], to url: URL) throws {
        #if os(macOS)
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("TodayFlowXLSX-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }

        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(
            at: root.appendingPathComponent("_rels", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fm.createDirectory(
            at: root.appendingPathComponent("xl/_rels", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fm.createDirectory(
            at: root.appendingPathComponent("xl/worksheets", isDirectory: true),
            withIntermediateDirectories: true
        )

        let files: [String: String] = [
            "[Content_Types].xml": contentTypes,
            "_rels/.rels": rootRelationships,
            "xl/workbook.xml": workbook,
            "xl/_rels/workbook.xml.rels": workbookRelationships,
            "xl/styles.xml": styles,
            "xl/worksheets/sheet1.xml": sheetXML(items: items),
        ]
        for (path, contents) in files {
            try Data(contents.utf8).write(to: root.appendingPathComponent(path))
        }

        let output = url
        try? fm.removeItem(at: output)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = root
        process.arguments = ["-q", "-r", output.path, "."]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ExportError.zipFailed
        }
        #else
        throw ExportError.useWriteForExcel
        #endif
    }

    private var contentTypes: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        </Types>
        """
    }

    private var rootRelationships: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
    }

    private var workbook: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
                  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets><sheet name="Tasks" sheetId="1" r:id="rId1"/></sheets>
        </workbook>
        """
    }

    private var workbookRelationships: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """
    }

    private var styles: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <fonts count="2">
        <font><sz val="11"/><name val="Calibri"/></font>
        <font><b/><sz val="11"/><name val="Calibri"/></font>
        </fonts>
        <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
        <borders count="1"><border/></borders>
        <cellStyleXfs count="1"><xf/></cellStyleXfs>
        <cellXfs count="2"><xf/><xf fontId="1" applyFont="1"/></cellXfs>
        </styleSheet>
        """
    }

    private func sheetXML(items: [WorkItem]) -> String {
        let formatter = ISO8601DateFormatter()
        let header = [
            "id", "kind", "title", "parent_id", "status", "priority",
            "estimate_min", "start_at", "end_at", "completed_at", "display_order",
            "tags", "description", "summary",
        ]
        var rows = [rowXML(header, index: 1, header: true)]

        for (offset, item) in items.sorted(by: sortByCreatedAt).enumerated() {
            let values = [
                item.id.uuid.uuidString,
                item.kind.rawValue,
                item.title,
                item.parentId?.uuid.uuidString ?? "",
                item.status.rawValue,
                "P\(item.priority.rawValue)",
                item.estimatedMinutes.map(String.init) ?? "",
                formatter.string(from: item.startAt),
                formatter.string(from: item.endAt),
                item.completedAt.map(formatter.string(from:)) ?? "",
                item.displayOrder,
                item.tags.joined(separator: "; "),
                item.descriptionMd,
                item.summary,
            ]
            rows.append(rowXML(values, index: offset + 2, header: false))
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetData>\(rows.joined())</sheetData>
        </worksheet>
        """
    }

    private func rowXML(_ values: [String], index: Int, header: Bool) -> String {
        let cells = values.enumerated().map { column, value in
            let ref = "\(columnName(column))\(index)"
            let style = header ? " s=\"1\"" : ""
            let escaped = xmlEscape(value)
            return "<c r=\"\(ref)\"\(style) t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escaped)</t></is></c>"
        }
        return "<row r=\"\(index)\">\(cells.joined())</row>"
    }

    private func columnName(_ index: Int) -> String {
        var value = index + 1
        var result = ""
        while value > 0 {
            value -= 1
            result = String(UnicodeScalar(65 + value % 26)!) + result
            value /= 26
        }
        return result
    }

    private func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
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
