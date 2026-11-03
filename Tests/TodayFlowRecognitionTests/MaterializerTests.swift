import Foundation
import Testing
import TodayFlowCore
import TodayFlowRecognition

@Suite("Materializer")
struct MaterializerTests {
    private let attachments = URL(fileURLWithPath: "/tmp/todayflow-test-attachments", isDirectory: true)

    private func makeMaterializer(fail: Bool = false) -> (Materializer, FakeFileAccess) {
        let fake = FakeFileAccess(fail: fail)
        return (Materializer(fileAccess: fake, attachmentsDirectory: attachments), fake)
    }

    @Test("copiesFilePromisesIntoContainer")
    func copiesFilePromisesIntoContainer() {
        let (materializer, fake) = makeMaterializer()
        let recognized = RecognizedObject(type: .file, displayName: "budget.msg", reference: "/tmp/budget.msg")
        let source = DroppedObject(
            fileURL: URL(fileURLWithPath: "/tmp/budget.msg"),
            isFilePromise: true
        )

        let result = materializer.materialize(recognized, source: source)

        #expect(result.localCopyPath != nil)
        #expect(result.localCopyPath?.hasPrefix(attachments.path) == true)
        #expect(result.localCopyPath?.hasSuffix("-budget.msg") == true)
        #expect(result.reference == result.localCopyPath)
        #expect(fake.createdDirectories == [attachments])
        #expect(fake.copies.count == 1)
        #expect(fake.copies.first?.from == URL(fileURLWithPath: "/tmp/budget.msg"))
        #expect(fake.bookmarkRequests.isEmpty)
    }

    @Test("copiesTransientEmlEvenWithoutPromise")
    func copiesTransientEmlEvenWithoutPromise() {
        let (materializer, fake) = makeMaterializer()
        let recognized = RecognizedObject(type: .email, displayName: "Lunch.eml", reference: "/tmp/Lunch.eml")
        let source = DroppedObject(fileURL: URL(fileURLWithPath: "/tmp/Lunch.eml"))

        let result = materializer.materialize(recognized, source: source)

        #expect(result.localCopyPath?.hasSuffix("-Lunch.eml") == true)
        #expect(result.reference == result.localCopyPath)
        #expect(fake.copies.count == 1)
        #expect(fake.bookmarkRequests.isEmpty)
    }

    @Test("persistentFileGetsBookmarkNotCopy")
    func persistentFileGetsBookmarkNotCopy() {
        let (materializer, fake) = makeMaterializer()
        let recognized = RecognizedObject(type: .file, displayName: "Invoice.pdf", reference: "/tmp/Invoice.pdf")
        let source = DroppedObject(fileURL: URL(fileURLWithPath: "/tmp/Invoice.pdf"))

        let result = materializer.materialize(recognized, source: source)

        #expect(result.bookmark == Data([0x42]))
        #expect(result.localCopyPath == nil)
        #expect(result.reference == "/tmp/Invoice.pdf")
        #expect(fake.copies.isEmpty)
        #expect(fake.bookmarkRequests == [URL(fileURLWithPath: "/tmp/Invoice.pdf")])
    }

    @Test("folderGetsBookmark")
    func folderGetsBookmark() {
        let (materializer, fake) = makeMaterializer()
        let recognized = RecognizedObject(type: .folder, displayName: "Projects", reference: "/Users/afonso/Projects")
        let source = DroppedObject(
            fileURL: URL(fileURLWithPath: "/Users/afonso/Projects"),
            isDirectory: true
        )

        let result = materializer.materialize(recognized, source: source)

        #expect(result.bookmark == Data([0x42]))
        #expect(result.localCopyPath == nil)
        #expect(fake.copies.isEmpty)
        #expect(fake.bookmarkRequests == [URL(fileURLWithPath: "/Users/afonso/Projects")])
    }

    @Test("writesImageDataIntoContainer")
    func writesImageDataIntoContainer() {
        let (materializer, fake) = makeMaterializer()
        let recognized = RecognizedObject(type: .image, displayName: "Pasted image")
        let source = DroppedObject(imageData: Data([0x89, 0x50, 0x4E, 0x47]))

        let result = materializer.materialize(recognized, source: source)

        #expect(result.localCopyPath?.hasSuffix("-Pasted image.png") == true)
        #expect(result.reference == result.localCopyPath)
        #expect(fake.createdDirectories == [attachments])
        #expect(fake.writes.count == 1)
        #expect(fake.writes.first?.data == Data([0x89, 0x50, 0x4E, 0x47]))
        #expect(fake.copies.isEmpty)
    }

    @Test("urlObjectUntouched")
    func urlObjectUntouched() {
        let (materializer, fake) = makeMaterializer()
        let recognized = RecognizedObject(
            type: .url,
            displayName: "example.com",
            reference: "https://example.com"
        )
        let source = DroppedObject(url: URL(string: "https://example.com")!)

        let result = materializer.materialize(recognized, source: source)

        #expect(result == recognized)
        #expect(fake.createdDirectories.isEmpty)
        #expect(fake.copies.isEmpty)
        #expect(fake.writes.isEmpty)
        #expect(fake.bookmarkRequests.isEmpty)
    }

    @Test("failedCopyLeavesObjectUnchanged")
    func failedCopyLeavesObjectUnchanged() {
        let (materializer, _) = makeMaterializer(fail: true)
        let recognized = RecognizedObject(type: .file, displayName: "budget.msg", reference: "/tmp/budget.msg")
        let source = DroppedObject(
            fileURL: URL(fileURLWithPath: "/tmp/budget.msg"),
            isFilePromise: true
        )

        let result = materializer.materialize(recognized, source: source)

        #expect(result == recognized)
    }
}
