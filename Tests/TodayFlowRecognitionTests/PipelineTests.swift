import Foundation
import Testing
import UniformTypeIdentifiers
import TodayFlowCore
import TodayFlowRecognition

/// End-to-end drop-to-draft tests (driver.md §11, increment 3 acceptance).
///
/// The pipeline is built with fakes — never `.standard` — so the tests have
/// no disk side effects and a deterministic work calendar.
@Suite("RecognitionPipeline")
struct PipelineTests {
    /// Deterministic calendar: UTC, 09:00–17:00, Monday–Friday.
    private var calendar: WorkCalendar {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "UTC")!
        return WorkCalendar(calendar: gregorian)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.calendar.date(from: components)!
    }

    private func makePipeline(fail: Bool = false) -> (RecognitionPipeline, FakeFileAccess) {
        let fake = FakeFileAccess(fail: fail)
        let pipeline = RecognitionPipeline(
            recognizers: [
                OutlookEmailRecognizer(),
                MailEmailRecognizer(),
                CalendarEventRecognizer(),
                TeamsMessageRecognizer(),
                FolderRecognizer(),
                OfficeDocumentRecognizer(),
                PDFRecognizer(),
                ImageRecognizer(),
                WebURLRecognizer(),
                GenericFileRecognizer(),
                PlainTextRecognizer(),
            ],
            materializer: Materializer(
                fileAccess: fake,
                attachmentsDirectory: URL(fileURLWithPath: "/tmp/todayflow-test-attachments", isDirectory: true)
            ),
            calendar: calendar
        )
        return (pipeline, fake)
    }

    @Test("pdfDroppedAt1042GetsSameDayEndOfBusiness")
    func pdfDroppedAt1042GetsSameDayEndOfBusiness() {
        let (pipeline, fake) = makePipeline()
        // 2026-01-05 is a Monday, 10:42 is inside working hours.
        let droppedAt = date(2026, 1, 5, hour: 10, minute: 42)
        let object = DroppedObject(
            fileURL: URL(fileURLWithPath: "/tmp/Invoice-2026.pdf"),
            uti: UTType(filenameExtension: "pdf"),
            fileSize: 102_400
        )

        let draft = pipeline.process([object], at: droppedAt)

        #expect(draft.title == "Invoice-2026")
        #expect(draft.startAt == droppedAt)
        #expect(draft.endAt == date(2026, 1, 5, hour: 17, minute: 0))
        #expect(draft.priority == .default)
        #expect(draft.objects.count == 1)
        #expect(draft.objects[0].type == .file)
        #expect(draft.objects[0].bookmark == Data([0x42]))
        #expect(fake.copies.isEmpty)
    }

    @Test("emailDroppedAfterHoursGetsNextBusinessDay")
    func emailDroppedAfterHoursGetsNextBusinessDay() {
        let (pipeline, fake) = makePipeline()
        // Monday 18:30 is after 17:00 → end at Tuesday 17:00.
        let droppedAt = date(2026, 1, 5, hour: 18, minute: 30)
        let object = DroppedObject(
            fileURL: URL(fileURLWithPath: "/tmp/brief.eml"),
            fileData: Data(
                "Subject: Weekly brief\nFrom: a@example.com\nDate: Mon, 05 Jan 2026 18:30:00 +0000\n\nBody".utf8
            ),
            sourceApp: "com.apple.mail"
        )

        let draft = pipeline.process([object], at: droppedAt)

        #expect(draft.title == "Weekly brief")
        #expect(draft.endAt == date(2026, 1, 6, hour: 17, minute: 0))
        #expect(draft.objects[0].type == .email)
        // A `.eml` is transient: the materializer copies it into the container.
        #expect(draft.objects[0].localCopyPath != nil)
        #expect(fake.copies.count == 1)
    }

    @Test("dropAfterFridayHoursSkipsTheWeekend")
    func dropAfterFridayHoursSkipsTheWeekend() {
        let (pipeline, _) = makePipeline()
        // Friday 2026-01-09 18:30 → next working day is Monday 2026-01-12.
        let droppedAt = date(2026, 1, 9, hour: 18, minute: 30)
        let object = DroppedObject(fileURL: URL(fileURLWithPath: "/tmp/notes.txt"))

        let draft = pipeline.process([object], at: droppedAt)

        #expect(draft.endAt == date(2026, 1, 12, hour: 17, minute: 0))
    }

    @Test("threeFilesProduceOneDraftWithThreeAttachments")
    func threeFilesProduceOneDraftWithThreeAttachments() {
        let (pipeline, _) = makePipeline()
        let objects = [
            DroppedObject(fileURL: URL(fileURLWithPath: "/tmp/a.txt")),
            DroppedObject(fileURL: URL(fileURLWithPath: "/tmp/b.txt")),
            DroppedObject(fileURL: URL(fileURLWithPath: "/tmp/c.txt")),
        ]

        let draft = pipeline.process(objects, at: date(2026, 1, 5, hour: 10, minute: 0))

        #expect(draft.title == "a")
        #expect(draft.objects.count == 3)
        #expect(draft.attachments(for: UUIDv7.new()).count == 3)
    }

    @Test("firstMatchingRecognizerWins")
    func firstMatchingRecognizerWins() {
        let (pipeline, _) = makePipeline()
        // A `.eml` from Outlook belongs to OutlookEmailRecognizer (first in the
        // list); it rewrites the source app to "outlook", which
        // MailEmailRecognizer would never do.
        let object = DroppedObject(
            fileURL: URL(fileURLWithPath: "/tmp/x.eml"),
            fileData: Data("Subject: Hello\nFrom: carol@example.com\n\nHi".utf8),
            sourceApp: "com.microsoft.outlook"
        )

        let draft = pipeline.process([object], at: date(2026, 1, 5, hour: 10, minute: 0))

        #expect(draft.objects.count == 1)
        #expect(draft.objects[0].type == .email)
        #expect(draft.objects[0].sourceApp == "outlook")
    }

    @Test("unrecognizableObjectFallsBackToGenericFile")
    func unrecognizableObjectFallsBackToGenericFile() {
        let (pipeline, _) = makePipeline()
        let recognized = pipeline.recognize(DroppedObject())

        #expect(recognized.type == .file)
        #expect(recognized.displayName == "Dropped object")
    }

    @Test("singlePastedTextBecomesTheDescription")
    func singlePastedTextBecomesTheDescription() {
        let (pipeline, _) = makePipeline()
        let object = DroppedObject(text: "Buy milk\nand eggs")

        let draft = pipeline.process([object], at: date(2026, 1, 5, hour: 10, minute: 0))

        #expect(draft.title == "Buy milk")
        #expect(draft.descriptionMd == "Buy milk\nand eggs")
    }
}
