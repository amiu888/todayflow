import Foundation
import TodayFlowCore
import TodayFlowRecognition
import UniformTypeIdentifiers
import Vision

/// Reads the words in a screenshot or photo on the device (Vision), so a
/// shared or pasted Messages/Messenger screenshot can name its task and give
/// its to-dos. Nothing leaves the device.
public enum ScreenText {
    /// The text in the image, top to bottom; nil when there is none or the
    /// file isn't an image.
    public static func read(imageAt url: URL) async -> String? {
        guard isImage(url) else { return nil }
        return await recognize { VNImageRequestHandler(url: url) }
    }

    /// The text in pasted image bytes (PNG, JPEG, HEIC).
    public static func read(imageData data: Data) async -> String? {
        guard !data.isEmpty else { return nil }
        return await recognize { VNImageRequestHandler(data: data) }
    }

    private static func recognize(_ makeHandler: @escaping @Sendable () -> VNImageRequestHandler) async -> String? {
        await Task.detached(priority: .userInitiated) { () -> String? in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            guard (try? makeHandler().perform([request])) != nil else { return nil }
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : String(text.prefix(8_000))
        }.value
    }

    public static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    /// Gives each image in a drop the text read from it (`previewText`), so
    /// the title rules and Apple Intelligence can use what the screenshot says.
    public static func addText(to recognized: [RecognizedObject], from dropped: [DroppedObject]) async -> [RecognizedObject] {
        var result = recognized
        for index in result.indices where index < dropped.count {
            guard (result[index].previewText ?? "").isEmpty else { continue }
            let object = dropped[index]
            var text: String?
            if let file = object.fileURL {
                text = await read(imageAt: file)
            } else if let data = object.imageData {
                text = await read(imageData: data)
            }
            guard let text else { continue }
            result[index].previewText = text
        }
        return result
    }
}

/// To-dos for a task: Apple Intelligence when it's there, the plain rules
/// otherwise (or when it finds nothing), never repeating the checklist.
public enum ChecklistSuggestions {
    public static func suggest(
        title: String,
        text: String,
        existing: [String] = [],
        using suggester: (any ChecklistSuggesting)?
    ) async -> [String] {
        let ruled = TodoExtractor.clean(TodoExtractor.todos(in: text), existing: existing)
        guard let suggester, let todos = try? await suggester.suggestTodos(title: title, text: text) else { return ruled }
        var merged = TodoExtractor.clean(todos, existing: existing)
        // The model sometimes skips a plain ask the rules see ("Can you book
        // the dentist"); add those unless the model said the same in other words.
        for todo in ruled where !merged.contains(where: { sameTodo($0, todo) }) {
            merged.append(todo)
        }
        return Array(merged.prefix(TodoExtractor.limit))
    }

    /// Two to-dos are the same when most of the shorter one's words are in
    /// the other: "Book the dentist" and "Book a dentist appointment".
    static func sameTodo(_ a: String, _ b: String) -> Bool {
        let small: Set<String> = ["the", "a", "an", "to", "for", "of", "and", "my", "me", "your", "please", "on", "at", "by", "in"]
        func words(_ text: String) -> Set<String> {
            Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { !small.contains($0) })
        }
        let (x, y) = (words(a), words(b))
        guard !x.isEmpty, !y.isEmpty else { return false }
        let shared = x.intersection(y).count
        return Double(shared) / Double(min(x.count, y.count)) >= 0.6
    }

    /// The words a task's to-dos come from: its description and summary,
    /// plus the text of its screenshots and photos.
    public static func sourceText(for item: WorkItem, attachments: [Attachment], attachmentsDirectory: URL?) async -> String {
        var parts = [item.descriptionMd, item.summary].filter { !$0.isEmpty }
        for attachment in attachments where attachment.kind == .image || attachment.kind == .file {
            for path in [attachment.localCopyPath, attachment.reference].compactMap({ $0 }) {
                let url = URL(fileURLWithPath: path)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                if let text = await ScreenText.read(imageAt: url) { parts.append(text) }
                break
            }
        }
        return parts.joined(separator: "\n\n")
    }
}
