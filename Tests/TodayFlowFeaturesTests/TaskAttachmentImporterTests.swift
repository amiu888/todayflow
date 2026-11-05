import Foundation
import Testing
import TodayFlowCore
import TodayFlowFeatures
import TodayFlowRecognition

/// A `FileAccess` stub that never touches the disk.
private struct StubFileAccess: FileAccess {
    func isDirectory(_ url: URL) -> Bool? { nil }
    func size(of url: URL) -> Int64? { nil }
    func modificationDate(of url: URL) -> Date? { nil }
    func copy(from source: URL, to destination: URL) throws {}
    func write(_ data: Data, to url: URL) throws {}
    func securityScopedBookmark(for url: URL) -> Data? { Data([0x42]) }
    func url(fromSecurityScopedBookmark data: Data) -> URL? { nil }
    func createDirectory(_ url: URL) throws {}
}

private let importerNow = Date(timeIntervalSince1970: 1_800_000_000)

private func makeImporter(
    repository: any AttachmentRepository
) -> TaskAttachmentImporter {
    TaskAttachmentImporter(
        attachmentRepository: repository,
        materializer: Materializer(
            fileAccess: StubFileAccess(),
            attachmentsDirectory: URL(fileURLWithPath: "/tmp/todayflow-importer-tests")
        ),
        deviceId: "test-device",
        clock: { importerNow }
    )
}

struct TaskAttachmentImporterTests {
    @Test func add_savesOneAttachmentPerObject() async throws {
        let repository = InMemoryAttachmentRepository()
        let itemId = UUIDv7.new()
        let sourceURL = URL(string: "https://example.com/article")!
        let recognized = [
            RecognizedObject(
                type: .url,
                displayName: "example.com",
                reference: sourceURL.absoluteString
            ),
            RecognizedObject(type: .text, displayName: "Pasted text", previewText: "hello"),
        ]
        let sources = [
            DroppedObject(url: sourceURL, uti: .url),
            DroppedObject(text: "hello", uti: .plainText),
        ]

        let saved = try await makeImporter(repository: repository)
            .add(recognized, from: sources, to: itemId)

        #expect(saved.count == 2)
        #expect(saved.map(\.itemId) == [itemId, itemId])
        #expect(saved.allSatisfy { $0.deviceId == "test-device" })
        #expect(saved.allSatisfy { $0.createdAt == importerNow })

        let stored = await repository.all
        #expect(stored.count == 2)
        #expect(Set(stored.map(\.id)) == Set(saved.map(\.id)))
    }

    @Test func add_usesAlreadyMaterializedObjectWithoutCopyingAgain() async throws {
        let repository = InMemoryAttachmentRepository()
        let itemId = UUIDv7.new()
        let recognized = RecognizedObject(
            type: .file,
            displayName: "contract.pdf",
            reference: "/tmp/copied-contract.pdf",
            localCopyPath: "/tmp/copied-contract.pdf"
        )
        let source = DroppedObject(
            fileURL: URL(fileURLWithPath: "/tmp/original-contract.pdf"),
            isFilePromise: true
        )

        let saved = try await makeImporter(repository: repository)
            .add([recognized], from: [source], to: itemId)

        #expect(saved.count == 1)
        // The importer kept the pipeline's copy rather than materializing a
        // second one from the raw source.
        #expect(saved.first?.localCopyPath == "/tmp/copied-contract.pdf")
        #expect(saved.first?.reference == "/tmp/copied-contract.pdf")
    }

    @Test func add_mismatchedCountsThrows() async throws {
        let repository = InMemoryAttachmentRepository()
        let importer = makeImporter(repository: repository)
        let recognized = [RecognizedObject(type: .text, displayName: "text")]

        await #expect(throws: TaskAttachmentImporter.ImportError.mismatchedObjectCount) {
            try await importer.add(recognized, from: [], to: UUIDv7.new())
        }
        #expect(await repository.all.isEmpty)
    }
}
