import Foundation
import Testing
import TodayFlowCore

@Suite("CaptureDraftBuilder")
struct CaptureDraftTests {
    private var builder: CaptureDraftBuilder {
        CaptureDraftBuilder(calendar: TestDates.workCalendar)
    }

    @Test("title comes from the first non-empty suggestedTitle, else displayName, else New task")
    func titleFallbacks() {
        let monday1042 = TestDates.date(2026, 1, 5, hour: 10, minute: 42)

        // First object's suggestedTitle wins.
        let draft = builder.build(
            objects: [
                RecognizedObject(
                    type: .file, uti: "com.adobe.pdf", displayName: "Spec.pdf",
                    suggestedTitle: "Read spec"
                ),
                RecognizedObject(type: .file, displayName: "B.docx", suggestedTitle: "B"),
            ],
            at: monday1042
        )
        #expect(draft.title == "Read spec")

        // Blank suggestedTitles are skipped.
        let blank = builder.build(
            objects: [
                RecognizedObject(
                    type: .file, uti: "com.adobe.pdf", displayName: "Spec.pdf",
                    suggestedTitle: "   "
                ),
                RecognizedObject(type: .file, displayName: "B.docx", suggestedTitle: "B"),
            ],
            at: monday1042
        )
        #expect(blank.title == "B")

        // No suggestedTitles: fall back to the first display name.
        let noTitles = builder.build(
            objects: [
                RecognizedObject(type: .folder, displayName: "Design"),
                RecognizedObject(type: .file, displayName: "B.docx"),
            ],
            at: monday1042
        )
        #expect(noTitles.title == "Design")

        // Nothing at all: "New task".
        #expect(builder.build(objects: [], at: monday1042).title == "New task")
    }

    @Test("a single pasted text object becomes the description")
    func textBecomesDescription() {
        let now = TestDates.date(2026, 1, 5, hour: 10, minute: 42)
        let draft = builder.build(
            objects: [
                RecognizedObject(
                    type: .text,
                    displayName: "Pasted text",
                    suggestedTitle: "First line",
                    previewText: "First line\nsecond line"
                )
            ],
            at: now
        )
        #expect(draft.descriptionMd == "First line\nsecond line")
        #expect(draft.title == "First line")
    }

    @Test("text dropped alongside a file does not clobber the description")
    func textPlusFileKeepsEmptyDescription() {
        let now = TestDates.date(2026, 1, 5, hour: 10, minute: 42)
        let draft = builder.build(
            objects: [
                RecognizedObject(
                    type: .text, displayName: "Pasted text", previewText: "some notes"
                ),
                RecognizedObject(
                    type: .file, uti: "com.adobe.pdf", displayName: "Spec.pdf",
                    suggestedTitle: "Read spec"
                ),
            ],
            at: now
        )
        #expect(draft.descriptionMd == "")
        #expect(draft.title == "Read spec")
    }

    @Test("weekday drop before EOB ends at 17:00 the same day")
    func weekdayBeforeEOB() {
        // Acceptance criterion (driver.md §11): PDF at 10:42 on a weekday →
        // start 10:42, end 17:00, P3.
        let monday1042 = TestDates.date(2026, 1, 5, hour: 10, minute: 42)
        let draft = builder.build(
            objects: [RecognizedObject(
                    type: .file, uti: "com.adobe.pdf", displayName: "Spec.pdf",
                    suggestedTitle: "Spec"
                )],
            at: monday1042
        )
        #expect(draft.startAt == monday1042)
        #expect(draft.endAt == TestDates.date(2026, 1, 5, hour: 17))
        #expect(draft.priority == .normal)
    }

    @Test("weekday drop after EOB ends at 17:00 the next business day")
    func weekdayAfterEOB() {
        // Acceptance criterion (driver.md §11): email at 18:30 → end = 17:00
        // next business day.
        let monday1830 = TestDates.date(2026, 1, 5, hour: 18, minute: 30)
        let draft = builder.build(
            objects: [RecognizedObject(type: .email, displayName: "Mail")],
            at: monday1830
        )
        #expect(draft.endAt == TestDates.date(2026, 1, 6, hour: 17))
    }

    @Test("Friday after EOB rolls to Monday 17:00")
    func fridayAfterEOB() {
        let friday1830 = TestDates.date(2026, 1, 9, hour: 18, minute: 30)
        let draft = builder.build(
            objects: [RecognizedObject(type: .email, displayName: "Mail")],
            at: friday1830
        )
        #expect(draft.endAt == TestDates.date(2026, 1, 12, hour: 17))
    }

    @Test("weekend drop rolls to Monday 17:00")
    func weekend() {
        let saturday1000 = TestDates.date(2026, 1, 10, hour: 10)
        let draft = builder.build(
            objects: [RecognizedObject(type: .file, displayName: "F")],
            at: saturday1000
        )
        #expect(draft.endAt == TestDates.date(2026, 1, 12, hour: 17))
    }

    @Test("every object maps to one attachment for the saved item")
    func attachmentsMapping() {
        let now = TestDates.date(2026, 1, 5, hour: 10, minute: 42)
        let draft = builder.build(
            objects: [
                RecognizedObject(
                    type: .file, uti: "com.adobe.pdf", displayName: "Spec.pdf",
                    suggestedTitle: "Spec"
                ),
                RecognizedObject(type: .url, displayName: "example.com", reference: "https://example.com"),
                RecognizedObject(type: .text, displayName: "Pasted text", previewText: "notes"),
            ],
            at: now
        )
        let itemId = UUIDv7.new()
        let attachments = draft.attachments(for: itemId, at: now)
        #expect(attachments.count == 3)
        #expect(attachments.allSatisfy { $0.itemId == itemId })
        #expect(attachments.map(\.kind) == [.file, .url, .text])
        #expect(attachments[1].reference == "https://example.com")
        #expect(attachments[2].previewText == "notes")
        #expect(attachments.allSatisfy { $0.createdAt == now })
    }

    @Test("parentId is carried through")
    func parentIdCarried() {
        let parent = WorkItem(kind: .project, title: "P")
        let now = TestDates.date(2026, 1, 5, hour: 10, minute: 42)
        let draft = builder.build(
            objects: [RecognizedObject(type: .file, displayName: "F")],
            at: now,
            parentId: parent.id
        )
        #expect(draft.parentId == parent.id)
    }
}
