import Foundation
import Testing
import UniformTypeIdentifiers
import TodayFlowCore
import TodayFlowFeatures
import TodayFlowRecognition

/// Regression coverage for dragging a real PNG through recognition and save.
struct ImageDropIntegrationTests {
    /// 1×1 transparent PNG.
    private static let png = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    @Test @MainActor
    func pngFile_recognizesAsImageAndSavesAnAttachment() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodayFlowImageDrop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let image = root.appendingPathComponent("screenshot.png")
        try Self.png.write(to: image)
        let attachments = root.appendingPathComponent("Attachments", isDirectory: true)

        let dropped = DroppedObject(
            fileURL: image,
            isDirectory: false,
            uti: .png,
            fileSize: Int64(Self.png.count)
        )
        let recognized = RecognitionPipeline.standard.recognize(dropped)
        #expect(recognized.type == .image)
        #expect(recognized.displayName == "screenshot.png")

        let repository = InMemoryWorkItemRepository()
        let attachmentRepository = InMemoryAttachmentRepository()
        let model = CaptureViewModel(
            repository: repository,
            attachmentRepository: attachmentRepository,
            materializer: Materializer(
                fileAccess: FileManagerFileAccess(),
                attachmentsDirectory: attachments
            ),
            clock: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        model.prepare(dropped: [dropped], recognized: [recognized])
        model.draft.title = "Screenshot"

        await model.save()

        #expect(model.lastError == nil)
        let items = await repository.allItems()
        #expect(items.count == 1)
        #expect(items.first?.title == "Screenshot")

        let saved = await attachmentRepository.all
        #expect(saved.count == 1)
        #expect(saved.first?.kind == .image)
        #expect(saved.first?.displayName == "screenshot.png")
        #expect(saved.first?.reference == image.path)
        #expect(saved.first?.bookmark != nil)
    }
}
