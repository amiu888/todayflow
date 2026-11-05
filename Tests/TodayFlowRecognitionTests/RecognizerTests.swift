import Foundation
import Testing
import UniformTypeIdentifiers
import TodayFlowCore
import TodayFlowRecognition

@Suite("OutlookEmailRecognizer")
struct OutlookEmailRecognizerTests {
    private static let msgFixture = CfbBuilder()
        .adding(name: "__substg1.0_0037001F", data: Data("Q3 budget review\0".utf8))
        .adding(name: "__substg1.0_0065001F", data: Data("Carol <carol@example.com>\0".utf8))
        .adding(name: "__substg1.0_007D001F", data: Data("Please review the Q3 budget.\0".utf8))
        .adding(name: "__substg1.0_00760040", data: fileTime(2026, 1, 5, hour: 18, minute: 30))

    private static func fileTime(_ year: Int, _ month: Int, _ day: Int, hour: Int, minute: Int) -> Data {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: components)!
        let ticks = Int64((date.timeIntervalSince1970 + 11_644_473_600) * 10_000_000)
        var data = Data()
        for i in 0..<8 {
            data.append(UInt8((ticks >> (8 * i)) & 0xFF))
        }
        return data
    }

    @Test("handlesMsgFilesAndOutlookLinks")
    func handlesMsgFilesAndOutlookLinks() {
        let recognizer = OutlookEmailRecognizer()
        #expect(recognizer.canHandle(DroppedObject(fileURL: URL(fileURLWithPath: "/tmp/a.msg"))))
        #expect(recognizer.canHandle(DroppedObject(url: URL(string: "ms-outlook://item/123")!)))
        #expect(recognizer.canHandle(DroppedObject(
            fileURL: URL(fileURLWithPath: "/tmp/a.eml"),
            sourceApp: "com.microsoft.outlook"
        )))
        // A `.eml` from Apple Mail belongs to MailEmailRecognizer.
        #expect(!recognizer.canHandle(DroppedObject(
            fileURL: URL(fileURLWithPath: "/tmp/a.eml"),
            sourceApp: "com.apple.mail"
        )))
    }

    @Test("recognizesMsgWithParsedFields")
    func recognizesMsgWithParsedFields() {
        let object = DroppedObject(
            fileURL: URL(fileURLWithPath: "/tmp/budget.msg"),
            isFilePromise: true,
            fileData: Self.msgFixture.build(),
            sourceApp: "com.microsoft.outlook"
        )
        let recognized = OutlookEmailRecognizer().recognize(object)

        #expect(recognized.type == .email)
        #expect(recognized.displayName == "Q3 budget review")
        #expect(recognized.suggestedTitle == "Q3 budget review")
        #expect(recognized.sourceApp == "outlook")
        #expect(recognized.metadata[MetadataKeys.sender] == "Carol <carol@example.com>")
        #expect(recognized.metadata[MetadataKeys.receivedAt] != nil)
        #expect(recognized.previewText == "Please review the Q3 budget.")
    }

    @Test("recognizesDeepLink")
    func recognizesDeepLink() {
        let object = DroppedObject(url: URL(string: "ms-outlook://item/abc")!)
        let recognized = OutlookEmailRecognizer().recognize(object)
        #expect(recognized.type == .email)
        #expect(recognized.displayName == "Outlook email")
        #expect(recognized.reference == "ms-outlook://item/abc")
    }
}

@Suite("MailEmailRecognizer")
struct MailEmailRecognizerTests {
    private static let eml = """
        From: Dave <dave@example.com>
        To: me@example.com
        Subject: Lunch?
        Date: Mon, 05 Jan 2026 12:00:00 +0000
        Message-ID: <dave-1@example.com>

        Want to grab lunch?
        """

    @Test("handlesMessageLinksAndNonOutlookEml")
    func handlesMessageLinksAndNonOutlookEml() {
        let recognizer = MailEmailRecognizer()
        #expect(recognizer.canHandle(DroppedObject(url: URL(string: "message://a/b")!)))
        #expect(recognizer.canHandle(DroppedObject(
            fileURL: URL(fileURLWithPath: "/tmp/a.eml"),
            sourceApp: "com.apple.mail"
        )))
        #expect(recognizer.canHandle(DroppedObject(fileURL: URL(fileURLWithPath: "/tmp/a.eml"))))
        #expect(!recognizer.canHandle(DroppedObject(
            fileURL: URL(fileURLWithPath: "/tmp/a.eml"),
            sourceApp: "com.microsoft.outlook"
        )))
    }

    @Test("recognizesEmlWithParsedFields")
    func recognizesEmlWithParsedFields() {
        let object = DroppedObject(
            fileURL: URL(fileURLWithPath: "/tmp/lunch.eml"),
            fileData: Data(Self.eml.utf8),
            sourceApp: "com.apple.mail"
        )
        let recognized = MailEmailRecognizer().recognize(object)

        #expect(recognized.type == .email)
        #expect(recognized.displayName == "Lunch?")
        #expect(recognized.suggestedTitle == "Lunch?")
        #expect(recognized.sourceApp == "com.apple.mail")
        #expect(recognized.metadata[MetadataKeys.from] == "Dave <dave@example.com>")
        #expect(recognized.metadata[MetadataKeys.to] == "me@example.com")
        #expect(recognized.metadata[MetadataKeys.messageId] == "<dave-1@example.com>")
        #expect(recognized.previewText?.hasPrefix("Want to grab lunch?") == true)
    }
}

@Suite("CalendarEventRecognizer")
struct CalendarEventRecognizerTests {
    private static let ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        SUMMARY:Design review
        DTSTART;TZID=America/New_York:20260105T103000
        DTEND;TZID=America/New_York:20260105T110000
        LOCATION:Conference room 4
        ORGANIZER;CN=Alice:mailto:alice@example.com
        URL:https://teams.microsoft.com/l/meetup-join/xyz
        END:VEVENT
        END:VCALENDAR
        """

    @Test("handlesIcsFilesAndWebcalLinks")
    func handlesIcsFilesAndWebcalLinks() {
        let recognizer = CalendarEventRecognizer()
        #expect(recognizer.canHandle(DroppedObject(fileURL: URL(fileURLWithPath: "/tmp/a.ics"))))
        #expect(recognizer.canHandle(DroppedObject(url: URL(string: "webcal://calendar.example.com/cal.ics")!)))
        #expect(!recognizer.canHandle(DroppedObject(fileURL: URL(fileURLWithPath: "/tmp/a.txt"))))
    }

    @Test("recognizesIcsWithParsedFields")
    func recognizesIcsWithParsedFields() {
        let object = DroppedObject(
            fileURL: URL(fileURLWithPath: "/tmp/review.ics"),
            fileData: Data(Self.ics.utf8),
            sourceApp: "com.apple.iCal"
        )
        let recognized = CalendarEventRecognizer().recognize(object)

        #expect(recognized.type == .calendarEvent)
        #expect(recognized.displayName == "Design review")
        #expect(recognized.suggestedTitle == "Design review")
        #expect(recognized.metadata[MetadataKeys.startAt] != nil)
        #expect(recognized.metadata[MetadataKeys.endAt] != nil)
        #expect(recognized.metadata[MetadataKeys.location] == "Conference room 4")
        #expect(recognized.metadata[MetadataKeys.organizer] == "Alice <alice@example.com>")
        #expect(recognized.metadata[MetadataKeys.joinLink] == "https://teams.microsoft.com/l/meetup-join/xyz")
        #expect(recognized.previewText == "Conference room 4")
    }

    @Test("recognizesWebcalLink")
    func recognizesWebcalLink() {
        let object = DroppedObject(url: URL(string: "webcal://calendar.example.com/cal.ics")!)
        let recognized = CalendarEventRecognizer().recognize(object)
        #expect(recognized.type == .calendarEvent)
        #expect(recognized.reference == "webcal://calendar.example.com/cal.ics")
    }
}

@Suite("TeamsMessageRecognizer")
struct TeamsMessageRecognizerTests {
    @Test("handlesTeamsLinksAndTeamsText")
    func handlesTeamsLinksAndTeamsText() {
        let recognizer = TeamsMessageRecognizer()
        #expect(recognizer.canHandle(DroppedObject(url: URL(string: "msteams://entity/conversation/1")!)))
        #expect(recognizer.canHandle(DroppedObject(url: URL(string: "https://teams.microsoft.com/l/chat/1")!)))
        #expect(recognizer.canHandle(DroppedObject(text: "hello", sourceApp: "com.microsoft.teams")))
        #expect(!recognizer.canHandle(DroppedObject(text: "hello", sourceApp: "com.apple.Safari")))
        #expect(!recognizer.canHandle(DroppedObject(text: "hello")))
    }

    @Test("usesFirstLineAsTitle")
    func usesFirstLineAsTitle() {
        let object = DroppedObject(text: "Deploy finished\nsecond line", sourceApp: "com.microsoft.teams")
        let recognized = TeamsMessageRecognizer().recognize(object)
        #expect(recognized.type == .teamsMessage)
        #expect(recognized.suggestedTitle == "Deploy finished")
        #expect(recognized.previewText == "Deploy finished\nsecond line")
    }

    @Test("fallsBackToChannelChatTitle")
    func fallsBackToChannelChatTitle() {
        let object = DroppedObject(text: "   \n  ", sourceApp: "com.microsoft.teams")
        let recognized = TeamsMessageRecognizer().recognize(object)
        #expect(recognized.suggestedTitle == "Teams: channel/chat")
    }

    @Test("recognizesLink")
    func recognizesLink() {
        let object = DroppedObject(url: URL(string: "https://teams.microsoft.com/l/chat/1/2")!)
        let recognized = TeamsMessageRecognizer().recognize(object)
        #expect(recognized.type == .teamsMessage)
        #expect(recognized.metadata[MetadataKeys.link] == "https://teams.microsoft.com/l/chat/1/2")
    }
}

@Suite("FolderRecognizer")
struct FolderRecognizerTests {
    @Test("recognizesDirectories")
    func recognizesDirectories() {
        let object = DroppedObject(
            fileURL: URL(fileURLWithPath: "/Users/afonso/Documents/Projects"),
            isDirectory: true,
            fileSize: 1234
        )
        #expect(FolderRecognizer().canHandle(object))
        let recognized = FolderRecognizer().recognize(object)
        #expect(recognized.type == .folder)
        #expect(recognized.displayName == "Projects")
        #expect(recognized.suggestedTitle == "Projects")
        #expect(recognized.reference == "/Users/afonso/Documents/Projects")
        #expect(recognized.metadata[MetadataKeys.path] == "/Users/afonso/Documents/Projects")
    }

    @Test("doesNotHandleFiles")
    func doesNotHandleFiles() {
        #expect(!FolderRecognizer().canHandle(DroppedObject(
            fileURL: URL(fileURLWithPath: "/tmp/a.txt"),
            isDirectory: false
        )))
    }
}

@Suite("OfficeDocumentRecognizer")
struct OfficeDocumentRecognizerTests {
    @Test("recognizesDocx")
    func recognizesDocx() {
        let object = DroppedObject(
            fileURL: URL(fileURLWithPath: "/tmp/Proposal.docx"),
            uti: UTType(filenameExtension: "docx"),
            fileSize: 20_480
        )
        #expect(OfficeDocumentRecognizer().canHandle(object))
        let recognized = OfficeDocumentRecognizer().recognize(object)
        #expect(recognized.type == .file)
        #expect(recognized.displayName == "Proposal.docx")
        #expect(recognized.suggestedTitle == "Proposal")
        #expect(recognized.metadata[MetadataKeys.officeKind] == "word")
        #expect(recognized.metadata[MetadataKeys.size] == "20480")
    }

    @Test("recognizesXlsAndPpt")
    func recognizesXlsAndPpt() {
        let xls = DroppedObject(
            fileURL: URL(fileURLWithPath: "/tmp/Numbers.xls"),
            uti: UTType(filenameExtension: "xls")
        )
        #expect(OfficeDocumentRecognizer().canHandle(xls))
        #expect(OfficeDocumentRecognizer().recognize(xls).metadata[MetadataKeys.officeKind] == "excel")

        let ppt = DroppedObject(
            fileURL: URL(fileURLWithPath: "/tmp/Deck.pptx"),
            uti: UTType(filenameExtension: "pptx")
        )
        #expect(OfficeDocumentRecognizer().canHandle(ppt))
        #expect(OfficeDocumentRecognizer().recognize(ppt).metadata[MetadataKeys.officeKind] == "powerpoint")
    }

    @Test("doesNotHandlePdfs")
    func doesNotHandlePdfs() {
        #expect(!OfficeDocumentRecognizer().canHandle(DroppedObject(
            fileURL: URL(fileURLWithPath: "/tmp/a.pdf"),
            uti: UTType(filenameExtension: "pdf")
        )))
    }
}

@Suite("PDFRecognizer")
struct PDFRecognizerTests {
    @Test("recognizesPdfs")
    func recognizesPdfs() {
        let object = DroppedObject(
            fileURL: URL(fileURLWithPath: "/tmp/Invoice-2026.pdf"),
            uti: UTType(filenameExtension: "pdf"),
            fileSize: 102_400
        )
        #expect(PDFRecognizer().canHandle(object))
        let recognized = PDFRecognizer().recognize(object)
        #expect(recognized.type == .file)
        #expect(recognized.displayName == "Invoice-2026.pdf")
        #expect(recognized.suggestedTitle == "Invoice-2026")
        #expect(recognized.metadata[MetadataKeys.size] == "102400")
    }

    @Test("doesNotHandleOtherFiles")
    func doesNotHandleOtherFiles() {
        #expect(!PDFRecognizer().canHandle(DroppedObject(
            fileURL: URL(fileURLWithPath: "/tmp/a.txt"),
            uti: UTType(filenameExtension: "txt")
        )))
    }
}

@Suite("ImageRecognizer")
struct ImageRecognizerTests {
    @Test("recognizesImageFiles")
    func recognizesImageFiles() {
        let object = DroppedObject(
            fileURL: URL(fileURLWithPath: "/tmp/screenshot.png"),
            uti: UTType(filenameExtension: "png"),
            fileSize: 512
        )
        #expect(ImageRecognizer().canHandle(object))
        let recognized = ImageRecognizer().recognize(object)
        #expect(recognized.type == .image)
        #expect(recognized.displayName == "screenshot.png")
        #expect(recognized.suggestedTitle == "screenshot")
    }

    @Test("recognizesPastedImageData")
    func recognizesPastedImageData() {
        let object = DroppedObject(imageData: Data([0x89, 0x50, 0x4E, 0x47]))
        #expect(ImageRecognizer().canHandle(object))
        let recognized = ImageRecognizer().recognize(object)
        #expect(recognized.type == .image)
        #expect(recognized.displayName == "Pasted image")
    }
}

@Suite("WebURLRecognizer")
struct WebURLRecognizerTests {
    @Test("recognizesHttpUrls")
    func recognizesHttpUrls() {
        let object = DroppedObject(url: URL(string: "https://www.example.com/blog/post")!)
        #expect(WebURLRecognizer().canHandle(object))
        let recognized = WebURLRecognizer().recognize(object)
        #expect(recognized.type == .url)
        #expect(recognized.displayName == "example.com")
        #expect(recognized.suggestedTitle == "example.com")
        #expect(recognized.reference == "https://www.example.com/blog/post")
        #expect(recognized.metadata[MetadataKeys.domain] == "example.com")
    }

    @Test("doesNotHandleNonHttpSchemes")
    func doesNotHandleNonHttpSchemes() {
        #expect(!WebURLRecognizer().canHandle(DroppedObject(url: URL(string: "msteams://x")!)))
        #expect(!WebURLRecognizer().canHandle(DroppedObject(url: URL(string: "file:///tmp/a")!)))
    }
}

@Suite("GenericFileRecognizer")
struct GenericFileRecognizerTests {
    @Test("recognizesAnyOtherFile")
    func recognizesAnyOtherFile() {
        let object = DroppedObject(
            fileURL: URL(fileURLWithPath: "/tmp/notes.txt"),
            isDirectory: false,
            fileSize: 64
        )
        #expect(GenericFileRecognizer().canHandle(object))
        let recognized = GenericFileRecognizer().recognize(object)
        #expect(recognized.type == .file)
        #expect(recognized.displayName == "notes.txt")
        #expect(recognized.suggestedTitle == "notes")
        #expect(recognized.metadata[MetadataKeys.path] == "/tmp/notes.txt")
    }

    @Test("doesNotHandleDirectories")
    func doesNotHandleDirectories() {
        #expect(!GenericFileRecognizer().canHandle(DroppedObject(
            fileURL: URL(fileURLWithPath: "/tmp/a"),
            isDirectory: true
        )))
    }
}

@Suite("PlainTextRecognizer")
struct PlainTextRecognizerTests {
    @Test("usesFirstLineCappedAt80Chars")
    func usesFirstLineCappedAt80Chars() {
        let longLine = String(repeating: "a", count: 120)
        let object = DroppedObject(text: "\(longLine)\nsecond line")
        #expect(PlainTextRecognizer().canHandle(object))
        let recognized = PlainTextRecognizer().recognize(object)
        #expect(recognized.type == .text)
        #expect(recognized.suggestedTitle == String(repeating: "a", count: 80))
        #expect(recognized.previewText == "\(longLine)\nsecond line")
    }

    @Test("skipsEmptyLeadingLines")
    func skipsEmptyLeadingLines() {
        let object = DroppedObject(text: "\n\n  Real first line  ")
        let recognized = PlainTextRecognizer().recognize(object)
        #expect(recognized.suggestedTitle == "Real first line")
    }
}

@Test("message links keep the pasteboard email text and headers")
func messageLinkKeepsText() {
    let text = """
        Subject: Q3 budget review
        From: Carol <carol@example.com>
        To: Afonso <afonso@example.com>

        Please review the Q3 budget and send the totals by Friday.
        """
    let object = DroppedObject(
        url: URL(string: "message://%3C123@example.com%3E")!,
        text: text,
        sourceApp: "com.apple.mail",
        uti: .url
    )

    let recognized = MailEmailRecognizer().recognize(object)

    #expect(recognized.type == .email)
    #expect(recognized.suggestedTitle == "Q3 budget review")
    #expect(recognized.metadata[MetadataKeys.from] == "Carol <carol@example.com>")
    #expect(recognized.previewText?.contains("vendor") == false)
    #expect(recognized.previewText?.contains("Q3 budget") == true)
}

@Suite("TeamsMessageRecognizer parsing")
struct TeamsMessageParsingTests {
    @Test func parsesSenderTimeAndMessage() {
        let object = DroppedObject(
            text: "Microsoft Teams\nJane Doe\n10:30 AM\nCan you review the deck?",
            sourceApp: "com.microsoft.teams2"
        )
        let recognized = TeamsMessageRecognizer().recognize(object)

        #expect(recognized.type == .teamsMessage)
        #expect(recognized.suggestedTitle == "Can you review the deck?")
        #expect(recognized.metadata[MetadataKeys.sender] == "Jane Doe")
        #expect(recognized.previewText == "Can you review the deck?")
    }

    @Test func titleCaseFirstLineBecomesSender() {
        let object = DroppedObject(
            text: "Jane Doe\nCan you review the deck?",
            sourceApp: "com.apple.Safari"
        )
        let recognized = TeamsMessageRecognizer().recognize(object)

        #expect(recognized.suggestedTitle == "Can you review the deck?")
        #expect(recognized.metadata[MetadataKeys.sender] == "Jane Doe")
    }

    @Test func keepsOrdinaryFirstLineAsTitle() {
        let object = DroppedObject(
            text: "Deploy finished\nsecond line",
            sourceApp: "com.microsoft.teams"
        )
        let recognized = TeamsMessageRecognizer().recognize(object)
        #expect(recognized.suggestedTitle == "Deploy finished")
    }

    @Test func detectsTeamsContentWithoutASourceApp() {
        let text = "Microsoft Teams\nhttps://teams.microsoft.com/l/message/1"
        let object = DroppedObject(text: text)
        #expect(TeamsMessageRecognizer().canHandle(object))
        let recognized = TeamsMessageRecognizer().recognize(object)
        #expect(recognized.metadata[MetadataKeys.link] == "https://teams.microsoft.com/l/message/1")
    }
}
