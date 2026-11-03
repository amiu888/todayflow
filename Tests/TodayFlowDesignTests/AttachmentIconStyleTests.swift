import Foundation
import SwiftUI
import Testing
import TodayFlowCore
import TodayFlowDesign

/// driver.md §4 attachment icon table:
/// email→envelope, calendar event→calendar, Teams→chat bubble, PDF→red doc,
/// Excel→green spreadsheet, Word→blue doc, PowerPoint→orange slides,
/// image→thumbnail, folder→system folder icon, URL→favicon/globe fallback,
/// other file→system icon.
///
/// The app target swaps in real system icons / thumbnails / favicons where
/// available (driver.md §4: "real system icon where available + bundled SF
/// Symbol fallback"); these tests pin the fallback mapping, which keys on the
/// UTI first, then the file name extension, then the attachment kind
/// (driver.md §7: "never extension alone").
@Suite("AttachmentIconStyle")
struct AttachmentIconStyleTests {
    // Qualified: the Testing framework also defines an `Attachment` type.
    private func attachment(
        kind: TodayFlowCore.Attachment.Kind,
        uti: String? = nil,
        displayName: String = "item"
    ) -> TodayFlowCore.Attachment {
        TodayFlowCore.Attachment(itemId: .new(), kind: kind, uti: uti, displayName: displayName)
    }

    @Test("emailIsEnvelope")
    func emailIsEnvelope() {
        let style = AttachmentIconStyle.style(
            for: attachment(kind: .email, uti: "org.rfc822-message", displayName: "Invoice.eml")
        )
        #expect(style.symbolName == "envelope.fill")
        #expect(style.tintHex == nil)
        #expect(style.accessibilityName == "Email")
    }

    @Test("outlookMessageIsEnvelope")
    func outlookMessageIsEnvelope() {
        let style = AttachmentIconStyle.style(
            for: attachment(kind: .email, uti: "x-outlook-message", displayName: "Report.msg")
        )
        #expect(style.symbolName == "envelope.fill")
    }

    @Test("calendarEventIsCalendarInBlue")
    func calendarEventIsCalendarInBlue() {
        let style = AttachmentIconStyle.style(
            for: attachment(kind: .calendarEvent, uti: "com.apple.ics", displayName: "Standup.ics")
        )
        #expect(style.symbolName == "calendar")
        #expect(style.tintHex == "#2a78d6")
    }

    @Test("teamsMessageIsChatBubbleInViolet")
    func teamsMessageIsChatBubbleInViolet() {
        let style = AttachmentIconStyle.style(
            for: attachment(kind: .teamsMessage, displayName: "Thread in Design review")
        )
        #expect(style.symbolName == "message.fill")
        #expect(style.tintHex == "#6250d6")
    }

    @Test("pdfIsRedDocument")
    func pdfIsRedDocument() {
        let style = AttachmentIconStyle.style(
            for: attachment(kind: .file, uti: "com.adobe.pdf", displayName: "Report.pdf")
        )
        #expect(style.symbolName == "doc.fill")
        #expect(style.tintHex == "#d03b3b")
    }

    @Test("wordIsBlueDocument")
    func wordIsBlueDocument() {
        let style = AttachmentIconStyle.style(
            for: attachment(kind: .file, uti: "org.openxmlformats.wordprocessingml.document", displayName: "Brief.docx")
        )
        #expect(style.symbolName == "doc.text.fill")
        #expect(style.tintHex == "#2a78d6")
    }

    @Test("excelIsGreenSpreadsheet")
    func excelIsGreenSpreadsheet() {
        let style = AttachmentIconStyle.style(
            for: attachment(kind: .file, uti: "org.openxmlformats.spreadsheetml.sheet", displayName: "Budget.xlsx")
        )
        #expect(style.symbolName == "tablecells")
        #expect(style.tintHex == "#0ca30c")
    }

    @Test("powerPointIsOrangeSlides")
    func powerPointIsOrangeSlides() {
        let style = AttachmentIconStyle.style(
            for: attachment(kind: .file, uti: "org.openxmlformats.presentationml.presentation", displayName: "Deck.pptx")
        )
        #expect(style.symbolName == "play.rectangle.fill")
        #expect(style.tintHex == "#eb6834")
    }

    @Test("imageIsPhoto")
    func imageIsPhoto() {
        let style = AttachmentIconStyle.style(
            for: attachment(kind: .image, uti: "public.image", displayName: "Screenshot.png")
        )
        #expect(style.symbolName == "photo")
        #expect(style.tintHex == nil)
    }

    @Test("folderIsFolder")
    func folderIsFolder() {
        let style = AttachmentIconStyle.style(
            for: attachment(kind: .folder, uti: "public.folder", displayName: "Drop zone")
        )
        #expect(style.symbolName == "folder")
        #expect(style.tintHex == nil)
    }

    @Test("urlIsGlobe")
    func urlIsGlobe() {
        let style = AttachmentIconStyle.style(
            for: attachment(kind: .url, displayName: "https://example.com/post")
        )
        #expect(style.symbolName == "globe")
        #expect(style.tintHex == nil)
    }

    @Test("unknownFileFallsBackToNeutralDoc")
    func unknownFileFallsBackToNeutralDoc() {
        let style = AttachmentIconStyle.style(
            for: attachment(kind: .file, displayName: "archive.unknownext")
        )
        #expect(style.symbolName == "doc")
        #expect(style.tintHex == nil)
    }

    @Test("utiBeatsExtension")
    func utiBeatsExtension() {
        // The file name says PDF, but the UTI says image: the UTI wins.
        let style = AttachmentIconStyle.style(
            for: attachment(kind: .image, uti: "public.image", displayName: "weird.pdf")
        )
        #expect(style.symbolName == "photo")
    }

    @Test("extensionFallsBackWhenUtiIsMissing")
    func extensionFallsBackWhenUtiIsMissing() {
        let style = AttachmentIconStyle.style(
            for: attachment(kind: .file, uti: nil, displayName: "report.PDF")
        )
        #expect(style.symbolName == "doc.fill")
        #expect(style.tintHex == "#d03b3b")
    }

    @Test("tintFallsBackToSecondaryInkPerScheme")
    func tintFallsBackToSecondaryInkPerScheme() {
        let style = AttachmentIconStyle.style(
            for: attachment(kind: .url, displayName: "https://example.com")
        )
        #expect(style.tint(in: .light).resolve(in: EnvironmentValues()) !=
            style.tint(in: .dark).resolve(in: EnvironmentValues()))
    }
}
