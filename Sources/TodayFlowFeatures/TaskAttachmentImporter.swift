import Foundation
import TodayFlowCore
import TodayFlowRecognition

/// Adds dropped objects to an existing task as attachments (driver.md FR-04).
///
/// A drop onto a task row must never create a second task. This small use-case
/// object materializes each object (copying transient files, writing pasted
/// images, and bookmarking persistent files) and persists the resulting
/// `Attachment` rows. It is separate from `CaptureViewModel` so the behavior is
/// testable without SwiftUI.
public struct TaskAttachmentImporter: Sendable {
    /// `recognized` and `sources` must have the same count and order.
    public enum ImportError: Error, Equatable, Sendable {
        case mismatchedObjectCount
    }

    private let attachmentRepository: any AttachmentRepository
    private let materializer: Materializer
    private let deviceId: String
    private let clock: @Sendable () -> Date

    public init(
        attachmentRepository: any AttachmentRepository,
        materializer: Materializer,
        deviceId: String = "local",
        clock: @escaping @Sendable () -> Date = { .now }
    ) {
        self.attachmentRepository = attachmentRepository
        self.materializer = materializer
        self.deviceId = deviceId
        self.clock = clock
    }

    /// Materializes and saves one attachment per object, returning the saved
    /// rows in input order.
    @discardableResult
    public func add(
        _ recognized: [RecognizedObject],
        from sources: [DroppedObject],
        to itemId: UUIDv7
    ) async throws -> [Attachment] {
        guard recognized.count == sources.count else {
            throw ImportError.mismatchedObjectCount
        }

        var saved: [Attachment] = []
        saved.reserveCapacity(recognized.count)
        let now = clock()

        for (recognizedObject, source) in zip(recognized, sources) {
            // The drop pipeline may already have copied/bookmarked the object;
            // materializing again would create a second transient copy.
            let object = recognizedObject.localCopyPath == nil
                && recognizedObject.bookmark == nil
                ? materializer.materialize(recognizedObject, source: source)
                : recognizedObject

            var attachment = object.attachment(for: itemId, at: now)
            attachment.deviceId = deviceId
            attachment.metadata["origin"] = "drop"
            if let sourceApp = source.sourceApp {
                attachment.sourceApp = sourceApp
            }
            if let uti = source.uti {
                attachment.metadata["drop_uti"] = uti.identifier
            }
            try await attachmentRepository.save(attachment)
            saved.append(attachment)
        }

        return saved
    }
}

/// Cross-feature notifications with no payload. The app posts these after a
/// drop mutates rows the live Today query does not observe directly.
public enum TodayFlowEvents {
    /// An attachment was added to an existing task (FR-04).
    public static let attachmentsChanged = Notification.Name("TodayFlow.attachmentsChanged")
    /// A task was created/updated outside the Today list's own actions.
    public static let itemsChanged = Notification.Name("TodayFlow.itemsChanged")
    /// A capture finished; `userInfo["message"]` is shown as a confirmation.
    public static let captureSaved = Notification.Name("TodayFlow.captureSaved")
    /// A task reminder was set or cleared; reschedule notifications.
    public static let remindersChanged = Notification.Name("TodayFlow.remindersChanged")
}
