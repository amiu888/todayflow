#if os(iOS)
import Foundation
import TodayFlowAI
import TodayFlowCore
import TodayFlowFeatures
import TodayFlowRecognition

/// Screenshot → task on the iPhone, for Paste and for Share: read the words
/// in screenshots on the device, let Apple Intelligence (when it's on) name
/// the task and summarize it, and find the to-dos. Nothing leaves the phone.
@MainActor
enum PhoneSmartCapture {
    /// Apple Intelligence's title and summary, when the iPhone has it.
    static var taskSuggester: (any TaskSuggesting)? {
        if #available(iOS 26.0, *), AppleTaskSuggester.isAvailable { return AppleTaskSuggester() }
        return nil
    }

    /// Apple Intelligence's to-do list, when the iPhone has it; otherwise
    /// `ChecklistSuggestions` uses the plain rules.
    static var checklistSuggester: (any ChecklistSuggesting)? {
        if #available(iOS 26.0, *), AppleChecklistSuggester.isAvailable { return AppleChecklistSuggester() }
        return nil
    }

    static var hasAppleIntelligence: Bool { taskSuggester != nil }

    /// What a paste or share holds, read and understood.
    struct Reading {
        var recognized: [RecognizedObject]
        /// Everything the items say, screenshots included.
        var text: String
        var hasScreenText: Bool
    }

    static func read(_ dropped: [DroppedObject], pipeline: RecognitionPipeline) async -> Reading {
        let recognized = await ScreenText.addText(
            to: dropped.map { pipeline.recognize($0) },
            from: dropped
        )
        let screenText = recognized.compactMap(\.previewText).filter { !$0.isEmpty }
        let typed = dropped.compactMap(\.text).filter { !$0.isEmpty }
        return Reading(
            recognized: recognized,
            text: (typed + screenText).joined(separator: "\n\n"),
            hasScreenText: dropped.indices.contains { index in
                (dropped[index].imageData != nil || dropped[index].fileURL.map(ScreenText.isImage) == true)
                    && !(recognized[index].previewText ?? "").isEmpty
            }
        )
    }

    /// Fills a capture from what was read: the rules' title first, then
    /// Apple Intelligence's when it's there. A screenshot's words go in the
    /// description when nothing else does, so the task can be found by them.
    static func prepare(_ capture: CaptureViewModel, dropped: [DroppedObject], reading: Reading) async {
        capture.prepare(dropped: dropped, recognized: reading.recognized)
        if let suggester = taskSuggester {
            capture.assistant = suggester
            await capture.requestAISuggestion()
        }
        if capture.draft.descriptionMd.isEmpty, reading.hasScreenText {
            capture.draft.descriptionMd = reading.recognized.compactMap(\.previewText).joined(separator: "\n\n")
        }
    }

    static func todos(title: String, reading: Reading) async -> [String] {
        await ChecklistSuggestions.suggest(title: title, text: reading.text, using: checklistSuggester)
    }

    /// Saves picked to-dos as the new task's checklist.
    static func addChecklist(_ todos: [String], to itemId: UUIDv7, repository: any ActionItemRepository) async {
        for (order, text) in TodoExtractor.clean(todos).enumerated() {
            try? await repository.save(ActionItem(itemId: itemId, text: text, sortOrder: order))
        }
    }
}
#endif
