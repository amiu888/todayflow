import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import TodayFlowCore
import TodayFlowRecognition
import UniformTypeIdentifiers
@testable import TodayFlowFeatures

/// Screenshot → task and the AI to-do list: reading a screenshot's words,
/// finding the to-dos in them, and adding the ones picked to the checklist.
struct ChecklistSuggestionTests {
    // MARK: - To-dos without AI

    @Test func listLines_becomeTodos() {
        let text = """
        Notes from the call
        - Book flights to Lisbon
        • send the deck to Maria
        1. Renew the passport
        2) Pay the deposit
        [ ] Call the hotel
        """
        #expect(TodoExtractor.todos(in: text) == [
            "Book flights to Lisbon", "Send the deck to Maria", "Renew the passport", "Pay the deposit", "Call the hotel",
        ])
    }

    @Test func askingSentencesInAChat_becomeTodos() {
        let chat = """
        Maria
        Hey! Can you send me the invoice by Friday? Thanks.
        Also please book the meeting room for Tuesday.
        Don't forget to bring the keys.
        Sounds good, see you then.
        """
        #expect(TodoExtractor.todos(in: chat) == [
            "Send me the invoice by Friday", "Book the meeting room for Tuesday", "Bring the keys",
        ])
    }

    @Test func chatLinesWithTheSendersName_stillGiveTheirTodos() {
        let chat = """
        Maria: Can you book the dentist?
        Mom - please call grandma tonight
        John Smith: Remember to water the plants.
        Note: this is fine
        """
        #expect(TodoExtractor.todos(in: chat) == ["Book the dentist", "Call grandma tonight", "Water the plants"])
    }

    @Test func plainChatter_hasNoTodos() {
        #expect(TodoExtractor.todos(in: "Haha yes\nSee you tomorrow!\nGreat game last night.").isEmpty)
    }

    @Test func clean_dropsRepeatsExistingItemsAndKeepsAtMostEight() {
        let many = (1...12).map { "Step number \($0)" } + ["step NUMBER 1.", "  ", "ok"]
        let cleaned = TodoExtractor.clean(many, existing: ["Step number 2"])
        #expect(cleaned.count == 8)
        #expect(cleaned.first == "Step number 1")
        #expect(!cleaned.contains("Step number 2"))
        #expect(!cleaned.contains("ok"))
    }

    // MARK: - With and without Apple Intelligence

    struct FakeSuggester: ChecklistSuggesting {
        var todos: [String] = []
        var fails = false
        func suggestTodos(title: String, text: String) async throws -> [String] {
            if fails { throw CancellationError() }
            return todos
        }
    }

    @Test func theModelsTodos_areUsed_andCleaned() async {
        let todos = await ChecklistSuggestions.suggest(
            title: "Trip", text: "whatever",
            existing: ["Book flights"],
            using: FakeSuggester(todos: ["book flights", "renew passport.", "Renew passport"])
        )
        #expect(todos == ["Renew passport"]) // "whatever" has no asks of its own
    }

    @Test func aTodoTheModelMissed_isAddedFromTheRules_butNotTwice() async {
        let text = "Maria: Can you book the dentist? Please renew the parking permit."
        let todos = await ChecklistSuggestions.suggest(
            title: "", text: text,
            using: FakeSuggester(todos: ["Renew parking permit before Friday"])
        )
        #expect(todos == ["Renew parking permit before Friday", "Book the dentist"])
    }

    @Test func sameTodo_inOtherWords() {
        #expect(ChecklistSuggestions.sameTodo("Book the dentist", "Book a dentist appointment"))
        #expect(ChecklistSuggestions.sameTodo("Renew the parking permit", "Renew parking permit before Friday"))
        #expect(!ChecklistSuggestions.sameTodo("Book the dentist", "Book flights"))
    }

    @Test func withoutAI_orWhenItFails_theRulesStillFindTheTodos() async {
        let text = "Can you call the bank? Please sign the form."
        let expected = ["Call the bank", "Sign the form"]
        #expect(await ChecklistSuggestions.suggest(title: "", text: text, using: nil) == expected)
        #expect(await ChecklistSuggestions.suggest(title: "", text: text, using: FakeSuggester(fails: true)) == expected)
        #expect(await ChecklistSuggestions.suggest(title: "", text: text, using: FakeSuggester(todos: [])) == expected)
    }

    // MARK: - Reading a screenshot

    /// A white PNG with black text, like a cropped chat screenshot.
    static func screenshot(_ lines: [String]) throws -> Data {
        let width = 1200, height = 120 * lines.count + 80
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica" as CFString, 56, nil)
        for (index, line) in lines.enumerated() {
            let attributed = NSAttributedString(string: line, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            ])
            context.textPosition = CGPoint(x: 40, y: height - 100 - index * 120)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func aScreenshotsWords_areRead_fromAFileAndFromPastedBytes() async throws {
        let png = try Self.screenshot(["Can you send the invoice", "by Friday please"])
        let fromBytes = try #require(await ScreenText.read(imageData: png))
        #expect(fromBytes.lowercased().contains("invoice"))
        #expect(fromBytes.lowercased().contains("friday"))

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(UUID().uuidString).png")
        try png.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let fromFile = try #require(await ScreenText.read(imageAt: file))
        #expect(fromFile.lowercased().contains("invoice"))
    }

    @Test func notAnImage_hasNoText() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("notes-\(UUID().uuidString).txt")
        try Data("Can you send the invoice".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(await ScreenText.read(imageAt: file) == nil)
    }

    @Test func aPastedScreenshot_givesItsTextToTheTitleRulesAndAI() async throws {
        let png = try Self.screenshot(["Please renew the parking permit"])
        let dropped = [DroppedObject(imageData: png, sourceApp: "Messages")]
        let recognized = dropped.map { RecognitionPipeline.standard.recognize($0) }
        let withText = await ScreenText.addText(to: recognized, from: dropped)
        #expect(withText.first?.previewText?.lowercased().contains("parking permit") == true)
    }

    @Test func aTasksScreenshots_feedItsTodos() async throws {
        let png = try Self.screenshot(["Can you call the plumber"])
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(UUID().uuidString).png")
        try png.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let item = WorkItem(title: "Flat", descriptionMd: "Please pay the rent.")
        let attachment = Attachment(itemId: item.id, kind: .image, displayName: "chat.png", reference: file.path, localCopyPath: file.path)
        let text = await ChecklistSuggestions.sourceText(for: item, attachments: [attachment], attachmentsDirectory: nil)
        let todos = await ChecklistSuggestions.suggest(title: item.title, text: text, using: nil)
        #expect(todos.contains("Pay the rent"))
        #expect(todos.contains { $0.lowercased().contains("plumber") })
    }

    // MARK: - Adding the picked to-dos

    @MainActor
    @Test func pickedTodos_areAddedAfterTheChecklist_withoutRepeats() async throws {
        let items = InMemoryWorkItemRepository()
        let actions = InMemoryActionItemRepository()
        let item = WorkItem(title: "Trip")
        try await items.save(item)
        let model = DetailViewModel(
            itemId: item.id, repository: items, linkRepository: InMemoryLinkRepository(),
            attachmentRepository: InMemoryAttachmentRepository(), actionRepository: actions
        )
        await model.load()
        await model.addAction("Book flights")

        await model.addActions(["book flights", "Renew passport", "Pack"])
        #expect(model.actions.map(\.text) == ["Book flights", "Renew passport", "Pack"])
        #expect(model.actions.map(\.sortOrder) == [0, 1, 2])
    }
}
