import Foundation
import SwiftUI
import TodayFlowCore

/// The SF Symbol + tint that renders an attachment (driver.md §4 attachment
/// icon table: email→envelope, calendar→calendar, Teams→chat bubble, PDF→red
/// doc, Excel→green spreadsheet, Word→blue doc, PowerPoint→orange slides,
/// image→photo, folder→folder, URL→globe, other→doc).
///
/// This is the *fallback* style: the app target prefers real system icons
/// (NSWorkspace), image thumbnails, and favicons, and falls back to this when
/// it cannot produce one (driver.md §4: "real system icon where available +
/// bundled SF Symbol fallback").
///
/// Resolution order (driver.md §7: "never extension alone"):
/// 1. the attachment's UTI, when present;
/// 2. the file name extension, lowercased;
/// 3. the attachment kind.
///
/// Tints use the reference palette's hues for document types (PDF red, Word
/// blue, Excel green, PowerPoint orange, calendar blue, Teams violet) and the
/// secondary ink for everything else. Two deliberate same-hue collisions —
/// PDF red vs the P1 priority red, PowerPoint orange vs the P2 priority
/// orange — are mitigated by placement (the title separates the priority dot
/// from the attachment icons) and by shape (dot vs symbol); hue is never the
/// only cue.
public struct AttachmentIconStyle: Sendable, Equatable {
    public var symbolName: String
    public var accessibilityName: String
    /// Hex tint; nil means the neutral secondary ink for the current scheme.
    public var tintHex: String?

    public init(symbolName: String, accessibilityName: String, tintHex: String? = nil) {
        self.symbolName = symbolName
        self.accessibilityName = accessibilityName
        self.tintHex = tintHex
    }

    /// The tint for the current color scheme (neutral = secondary ink).
    public func tint(in scheme: ColorScheme) -> Color {
        if let tintHex {
            return Color(hex: tintHex)
        }
        return Color(hex: scheme == .dark ? "#c3c2b7" : "#52514e")
    }

    // One fixed style per row of the driver.md §4 icon table.

    static let email = AttachmentIconStyle(symbolName: "envelope.fill", accessibilityName: "Email")
    static let calendar = AttachmentIconStyle(symbolName: "calendar", accessibilityName: "Calendar event", tintHex: "#2a78d6")
    static let teams = AttachmentIconStyle(symbolName: "message.fill", accessibilityName: "Teams message", tintHex: "#6250d6")
    static let pdf = AttachmentIconStyle(symbolName: "doc.fill", accessibilityName: "PDF document", tintHex: "#d03b3b")
    static let word = AttachmentIconStyle(symbolName: "doc.text.fill", accessibilityName: "Word document", tintHex: "#2a78d6")
    static let excel = AttachmentIconStyle(symbolName: "tablecells", accessibilityName: "Spreadsheet", tintHex: "#0ca30c")
    static let powerPoint = AttachmentIconStyle(symbolName: "play.rectangle.fill", accessibilityName: "Presentation", tintHex: "#eb6834")
    static let image = AttachmentIconStyle(symbolName: "photo", accessibilityName: "Image")
    static let folder = AttachmentIconStyle(symbolName: "folder", accessibilityName: "Folder")
    static let url = AttachmentIconStyle(symbolName: "globe", accessibilityName: "Link")
    static let text = AttachmentIconStyle(symbolName: "doc.text", accessibilityName: "Text")
    static let file = AttachmentIconStyle(symbolName: "doc", accessibilityName: "File")

    public static func style(for attachment: Attachment) -> AttachmentIconStyle {
        style(uti: attachment.uti, displayName: attachment.displayName, kind: attachment.kind)
    }

    public static func style(uti: String?, displayName: String, kind: Attachment.Kind) -> AttachmentIconStyle {
        if let uti, let byUti = Self.style(uti: uti) {
            return byUti
        }
        let fileExtension = (displayName as NSString).pathExtension.lowercased()
        if !fileExtension.isEmpty, let byExtension = Self.style(fileExtension: fileExtension) {
            return byExtension
        }
        switch kind {
        case .email: return .email
        case .calendarEvent: return .calendar
        case .teamsMessage: return .teams
        case .url: return .url
        case .image: return .image
        case .folder: return .folder
        case .file: return .file
        case .text: return .text
        }
    }

    private static func style(uti: String) -> AttachmentIconStyle? {
        switch uti {
        case "org.rfc822-message", "x-outlook-message":
            return .email
        case "com.apple.ics":
            return .calendar
        case "com.adobe.pdf":
            return .pdf
        case "com.microsoft.word.doc",
            "org.openxmlformats.wordprocessingml.document",
            "org.openxmlformats.wordprocessingml.document.macroEnabled":
            return .word
        case "com.microsoft.excel.xls",
            "org.openxmlformats.spreadsheetml.sheet",
            "org.openxmlformats.spreadsheetml.sheet.macroEnabled":
            return .excel
        case "com.microsoft.powerpoint.ppt",
            "org.openxmlformats.presentationml.presentation",
            "org.openxmlformats.presentationml.presentation.macroEnabled":
            return .powerPoint
        case "public.image":
            return .image
        case "public.folder":
            return .folder
        case "public.url":
            return .url
        default:
            return nil
        }
    }

    private static func style(fileExtension: String) -> AttachmentIconStyle? {
        switch fileExtension {
        case "eml", "msg":
            return .email
        case "ics":
            return .calendar
        case "pdf":
            return .pdf
        case "doc", "docx":
            return .word
        case "xls", "xlsx":
            return .excel
        case "ppt", "pptx":
            return .powerPoint
        case "png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "webp":
            return .image
        default:
            return nil
        }
    }
}
