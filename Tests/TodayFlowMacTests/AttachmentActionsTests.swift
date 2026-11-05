#if canImport(AppKit)
import Foundation
import Testing
import TodayFlowCore
import TodayFlowMac

@Suite("AttachmentActions")
@MainActor
struct AttachmentActionsTests {
    private func email(
        sourceApp: String?,
        reference: String? = nil
    ) -> TodayFlowCore.Attachment {
        Attachment(
            itemId: UUIDv7.new(),
            kind: .email,
            displayName: "Q3 budget",
            sourceApp: sourceApp,
            reference: reference
        )
    }

    @Test func outlookEmailsOpenInOutlook() {
        #expect(
            AttachmentActions.preferredEmailBundleIdentifier(
                for: email(sourceApp: "outlook", reference: "/tmp/Q3.msg")
            ) == "com.microsoft.outlook"
        )
    }

    @Test func mailEmailsOpenInMail() {
        #expect(
            AttachmentActions.preferredEmailBundleIdentifier(
                for: email(sourceApp: "com.apple.mail")
            ) == "com.apple.mail"
        )
        #expect(
            AttachmentActions.preferredEmailBundleIdentifier(
                for: email(sourceApp: nil, reference: "message://%3C123@example.com%3E")
            ) == "com.apple.mail"
        )
    }

    @Test func nonEmailAttachmentsUseTheSystemDefault() {
        let attachment = TodayFlowCore.Attachment(
            itemId: UUIDv7.new(),
            kind: .file,
            displayName: "Invoice.pdf",
            sourceApp: "com.apple.Preview"
        )
        #expect(
            AttachmentActions.preferredEmailBundleIdentifier(for: attachment) == nil
        )
    }
}
#endif

@Suite("AttachmentActions email extensions")
@MainActor
struct AttachmentActionsExtensionTests {
    @Test func outlookMessagesUseMsg() {
        let attachment = TodayFlowCore.Attachment(
            itemId: UUIDv7.new(),
            kind: .email,
            uti: "x-outlook-message",
            displayName: "Budget",
            sourceApp: "outlook"
        )
        #expect(AttachmentActions.emailFileExtension(for: attachment) == "msg")
    }

    @Test func rfc822MessagesUseEml() {
        let attachment = TodayFlowCore.Attachment(
            itemId: UUIDv7.new(),
            kind: .email,
            uti: "org.rfc822-message",
            displayName: "Lunch",
            sourceApp: "com.apple.mail"
        )
        #expect(AttachmentActions.emailFileExtension(for: attachment) == "eml")
    }

    @Test func nonEmailHasNoEmailExtension() {
        let attachment = TodayFlowCore.Attachment(
            itemId: UUIDv7.new(),
            kind: .file,
            displayName: "Invoice.pdf"
        )
        #expect(AttachmentActions.emailFileExtension(for: attachment) == nil)
    }
}
