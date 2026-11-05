#if canImport(AppKit)
import Foundation
import Testing
import TodayFlowCore
import TodayFlowMac

@Suite("ContactsImporter file routing")
@MainActor
struct ContactsImporterTests {
    private func temporaryFile(_ name: String, _ contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodayFlowContacts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func tsvFileUsesTabDelimiter() throws {
        let url = try temporaryFile(
            "contacts.tsv",
            "First Name\tLast Name\tE-mail Address\nJane\tSmith\tjane@acme.com\n"
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let contacts = try ContactsImporter().importFile(at: url)

        #expect(contacts.count == 1)
        #expect(contacts.first?.firstName == "Jane")
        #expect(contacts.first?.lastName == "Smith")
        #expect(contacts.first?.emails == ["jane@acme.com"])
    }

    @Test func csvFileUsesCommaDelimiter() throws {
        let url = try temporaryFile(
            "contacts.csv",
            "First Name,Last Name,E-mail Address\nJane,Smith,jane@acme.com\n"
        )
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let contacts = try ContactsImporter().importFile(at: url)

        #expect(contacts.count == 1)
        #expect(contacts.first?.emails == ["jane@acme.com"])
    }
}
#endif
