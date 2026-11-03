import Foundation
import UniformTypeIdentifiers
import TodayFlowCore

/// Recognizes calendar events: `.ics` files and `webcal://` / `cals://`
/// links (driver.md §7).
public struct CalendarEventRecognizer: ObjectRecognizer {
    public init() {}

    public func canHandle(_ object: DroppedObject) -> Bool {
        if let url = object.url {
            let scheme = url.scheme?.lowercased()
            return scheme == "webcal" || scheme == "cals"
        }
        return object.fileURL?.pathExtension.lowercased() == "ics"
    }

    public func recognize(_ object: DroppedObject) -> RecognizedObject {
        if let url = object.url {
            return RecognizedObject(
                type: .calendarEvent,
                displayName: "Calendar event",
                sourceApp: object.sourceApp,
                reference: url.absoluteString
            )
        }

        let filename = object.fileURL?.lastPathComponent ?? "event"

        if let data = object.fileData, let event = IcsParser.parse(data) {
            var metadata: [String: String] = [:]
            if let start = event.start { metadata[MetadataKeys.startAt] = Iso8601.encode(start) }
            if let end = event.end { metadata[MetadataKeys.endAt] = Iso8601.encode(end) }
            if let location = event.location { metadata[MetadataKeys.location] = location }
            if let organizer = event.organizer {
                let display = event.organizerName.map { "\($0) <\(organizer)>" } ?? organizer
                metadata[MetadataKeys.organizer] = display
            }
            if let link = event.url { metadata[MetadataKeys.joinLink] = link }

            return RecognizedObject(
                type: .calendarEvent,
                uti: object.uti?.identifier ?? "com.apple.ics",
                displayName: event.summary ?? filename,
                sourceApp: object.sourceApp,
                reference: object.fileURL?.path,
                metadata: metadata,
                suggestedTitle: event.summary,
                previewText: event.location
            )
        }

        // Fallback when the file contents were not loaded.
        return RecognizedObject(
            type: .calendarEvent,
            uti: object.uti?.identifier,
            displayName: filename,
            sourceApp: object.sourceApp,
            reference: object.fileURL?.path
        )
    }
}
