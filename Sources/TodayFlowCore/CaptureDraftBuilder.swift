import Foundation

/// Builds a `CaptureDraft` from recognized objects (driver.md §7 step 4).
///
/// Pure and synchronous: this is the code path that must fit the 300 ms
/// drop-to-sheet budget (NFR-01), so it performs no I/O.
public struct CaptureDraftBuilder: Sendable {
    public var calendar: WorkCalendar

    public init(calendar: WorkCalendar = .standard) {
        self.calendar = calendar
    }

    public func build(
        objects: [RecognizedObject],
        at now: Date = .now,
        parentId: UUIDv7? = nil
    ) -> CaptureDraft {
        let title = objects.lazy
            .compactMap { $0.suggestedTitle?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            ?? objects.first?.displayName
            ?? "New task"

        // Pasted text becomes the description (driver.md §7: "Full text in
        // description") — but only when the single object is text, so we never
        // clobber a title the user dropped alongside it.
        let textObjects = objects.filter { $0.type == .text }
        let descriptionMd: String
        if objects.count == 1, let preview = textObjects.first?.previewText {
            descriptionMd = preview
        } else {
            descriptionMd = ""
        }

        return CaptureDraft(
            title: title,
            descriptionMd: descriptionMd,
            startAt: now,
            endAt: calendar.defaultEndAt(createdAt: now),
            priority: .default,
            parentId: parentId,
            objects: objects
        )
    }
}
