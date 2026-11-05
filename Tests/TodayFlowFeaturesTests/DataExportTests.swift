import Foundation
import Testing
import TodayFlowCore
import TodayFlowFeatures

struct DataExportTests {
    private var item: WorkItem {
        WorkItem(
            kind: .task,
            title: "Ship, then celebrate",
            descriptionMd: "Line one\nLine two",
            status: .inProgress,
            priority: .high,
            startAt: Date(timeIntervalSince1970: 1_800_000_000),
            endAt: Date(timeIntervalSince1970: 1_800_028_800),
            completedAt: nil,
            displayOrder: "a1",
            tags: ["launch", "q4"]
        )
    }

    @Test func json_roundTripsItems() throws {
        let item = self.item
        let data = try DataExport().data(for: [item], format: .json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([WorkItem].self, from: data)

        #expect(decoded.count == 1)
        #expect(decoded.first?.id == item.id)
        #expect(decoded.first?.title == item.title)
        #expect(decoded.first?.tags == item.tags)
        #expect(decoded.first?.descriptionMd == item.descriptionMd)
        // ISO-8601 export deliberately drops sub-second precision.
        #expect(decoded.first?.endAt.timeIntervalSince1970 == 1_800_028_800)
    }

    @Test func csv_hasHeaderAndEscapesSpecialCharacters() throws {
        let data = try DataExport().data(for: [item], format: .csv)
        let text = try #require(String(data: data, encoding: .utf8))
        let lines = text.components(separatedBy: "\r\n")

        #expect(lines.first?.hasPrefix("id,kind,title") == true)
        #expect(text.contains("\"Ship, then celebrate\""))
        #expect(text.contains("\"Line one\nLine two\""))
        #expect(text.contains("launch; q4"))
    }

    @Test func csv_sortsByCreationTime() throws {
        let later = WorkItem(title: "Later", createdAt: Date(timeIntervalSince1970: 2_000))
        let earlier = WorkItem(title: "Earlier", createdAt: Date(timeIntervalSince1970: 1_000))
        let data = try DataExport().data(for: [later, earlier], format: .csv)
        let text = try #require(String(data: data, encoding: .utf8))

        let earlierIndex = try #require(text.range(of: "Earlier")?.lowerBound)
        let laterIndex = try #require(text.range(of: "Later")?.lowerBound)
        #expect(earlierIndex < laterIndex)
    }

    @Test func xlsx_writesARealWorkbookWithTheTask() throws {
    let item = self.item
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("TodayFlow-\(UUID().uuidString).xlsx")
    defer { try? FileManager.default.removeItem(at: url) }

    try DataExport().write(items: [item], format: .xlsx, to: url)

    #expect(FileManager.default.fileExists(atPath: url.path))
    let header = try Data(contentsOf: url).prefix(2)
    #expect(header == Data([0x50, 0x4B])) // ZIP magic "PK"

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = ["-p", url.path, "xl/worksheets/sheet1.xml"]
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    process.waitUntilExit()
    let xml = String(
        decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
        as: UTF8.self
    )
    #expect(xml.contains("Ship, then celebrate"))
    #expect(xml.contains("P2"))
}
}

@Test func csv_includesTheTaskSummary() throws {
    let item = WorkItem(
        title: "Email task",
        summary: "Carol needs the vendor totals by Friday."
    )
    let data = try DataExport().data(for: [item], format: .csv)
    let csv = String(decoding: data, as: UTF8.self)
    #expect(csv.contains("summary"))
    #expect(csv.contains("Carol needs the vendor totals by Friday."))
}
