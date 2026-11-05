import Foundation
import TodayFlowCore

/// The drop-to-draft pipeline (driver.md §7): classify each dropped object
/// with the first matching recognizer, materialize transient items, and
/// combine everything into a `CaptureDraft`.
///
/// The whole run must stay under 300 ms (NFR-01); everything slower (URL
/// titles, text extraction) lives in the async `Enricher`.
///
/// ⌘/⌥-drop splitting ("this item only") is a UI concern of the quick-add
/// sheet (driver.md §11 increment 6), not a pipeline concern.
public struct RecognitionPipeline: Sendable {
    public var recognizers: [any ObjectRecognizer]
    public var materializer: Materializer
    public var calendar: WorkCalendar

    public init(
        recognizers: [any ObjectRecognizer],
        materializer: Materializer,
        calendar: WorkCalendar
    ) {
        self.recognizers = recognizers
        self.materializer = materializer
        self.calendar = calendar
    }

    /// The production pipeline: the eleven recognizers of driver.md §7 in
    /// priority order, a `FileManager` materializer writing into the app's
    /// `Attachments/` container, and the standard work calendar.
    ///
    /// Computed (not `static let`) because the pieces are `any`/class-backed
    /// and a stored `let` of non-`Sendable`-proven types would not compile
    /// under strict concurrency.
    public static var standard: RecognitionPipeline {
        let fileAccess = FileManagerFileAccess()
        let attachmentsDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("TodayFlow", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("TodayFlow-Attachments", isDirectory: true)
        return RecognitionPipeline(
            recognizers: [
                OutlookEmailRecognizer(),
                MailEmailRecognizer(),
                ContactRecognizer(),
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
                fileAccess: fileAccess,
                attachmentsDirectory: attachmentsDirectory
            ),
            calendar: .standard
        )
    }

    /// Runs the pipeline over a drop.
    public func process(
        _ objects: [DroppedObject],
        at now: Date = .now,
        parentId: UUIDv7? = nil
    ) -> CaptureDraft {
        let recognized = objects.map { object in
            let recognized = recognize(object)
            return materializer.materialize(recognized, source: object)
        }
        return CaptureDraftBuilder(calendar: calendar).build(
            objects: recognized,
            at: now,
            parentId: parentId
        )
    }

    /// Classifies one object with the first matching recognizer, falling back
    /// to a best-guess type so a drop never loses an object.
    public func recognize(_ object: DroppedObject) -> RecognizedObject {
        if let recognizer = recognizers.first(where: { $0.canHandle(object) }) {
            return recognizer.recognize(object)
        }
        return Self.fallback(for: object)
    }

    private static func fallback(for object: DroppedObject) -> RecognizedObject {
        if let fileURL = object.fileURL {
            let name = fileURL.lastPathComponent
            return RecognizedObject(
                type: .file,
                displayName: name,
                sourceApp: object.sourceApp,
                reference: fileURL.path,
                suggestedTitle: fileURL.deletingPathExtension().lastPathComponent
            )
        }
        if let url = object.url {
            return RecognizedObject(
                type: .url,
                displayName: url.absoluteString,
                sourceApp: object.sourceApp,
                reference: url.absoluteString
            )
        }
        if let text = object.text {
            return RecognizedObject(
                type: .text,
                displayName: "Pasted text",
                sourceApp: object.sourceApp,
                suggestedTitle: text
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .first { !$0.isEmpty }
                    .map { String($0.prefix(80)) },
                previewText: text
            )
        }
        if object.imageData != nil {
            return RecognizedObject(
                type: .image,
                displayName: "Pasted image",
                sourceApp: object.sourceApp
            )
        }
        return RecognizedObject(type: .file, displayName: "Dropped object")
    }
}
