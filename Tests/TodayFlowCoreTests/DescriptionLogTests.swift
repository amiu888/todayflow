import Foundation
import Testing
import TodayFlowCore

@Suite("Description notes")
struct DescriptionLogTests {
    private let created = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func oldTextIsOneNote_datedWhenTheTaskWasCreated() {
        let notes = DescriptionLog.notes(in: "Plain old description.", createdAt: created)
        #expect(notes.count == 1)
        #expect(notes[0].isUndated)
        #expect(notes[0].date == created)
    }

    @Test func addingKeepsOldText_andListsNewestFirst() {
        var md = "First words."
        md = DescriptionLog.adding("Second", at: created.addingTimeInterval(60), to: md, createdAt: created)
        md = DescriptionLog.adding("Third", at: created.addingTimeInterval(120), to: md, createdAt: created)
        let notes = DescriptionLog.notes(in: md, createdAt: created)
        #expect(notes.map(\.text) == ["Third", "Second", "First words."])
        #expect(notes[0].date == created.addingTimeInterval(120))
        #expect(md.hasPrefix("First words."))
    }

    @Test func editingKeepsTheTime_andEmptyDeletes() throws {
        var md = DescriptionLog.adding("Draft", at: created, to: "", createdAt: created)
        let id = try #require(DescriptionLog.notes(in: md, createdAt: created).first?.id)
        md = DescriptionLog.updating(id, to: "Final", in: md, createdAt: created)
        let note = try #require(DescriptionLog.notes(in: md, createdAt: created).first)
        #expect(note.text == "Final")
        #expect(note.date == created)
        md = DescriptionLog.removing(note.id, from: md, createdAt: created)
        #expect(DescriptionLog.notes(in: md, createdAt: created).isEmpty)
    }

    @Test func plainText_hidesTheMarkers() {
        var md = "Intro"
        md = DescriptionLog.adding("Call **Ana**", at: created, to: md, createdAt: created)
        #expect(DescriptionLog.plainText(md) == "Intro\n\nCall **Ana**")
    }

    @Test func notesInTheSameSecond_getDifferentIds() {
        var md = DescriptionLog.adding("A", at: created, to: "", createdAt: created)
        md = DescriptionLog.adding("B", at: created, to: md, createdAt: created)
        let ids = DescriptionLog.notes(in: md, createdAt: created).map(\.id)
        #expect(Set(ids).count == 2)
    }
}
