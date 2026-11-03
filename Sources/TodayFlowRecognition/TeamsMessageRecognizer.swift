import Foundation
import UniformTypeIdentifiers
import TodayFlowCore

/// Recognizes Microsoft Teams messages: `msteams://` links, links to
/// `teams.microsoft.com`, and text copied from the Teams app (driver.md §7).
public struct TeamsMessageRecognizer: ObjectRecognizer {
    public init() {}

    public func canHandle(_ object: DroppedObject) -> Bool {
        if let url = object.url {
            if url.scheme?.lowercased() == "msteams" { return true }
            if url.host()?.contains("teams.microsoft.com") == true { return true }
        }
        if object.text != nil {
            return (object.sourceApp ?? "").localizedCaseInsensitiveContains("teams")
        }
        return false
    }

    public func recognize(_ object: DroppedObject) -> RecognizedObject {
        if let url = object.url {
            return RecognizedObject(
                type: .teamsMessage,
                displayName: "Teams message",
                sourceApp: "teams",
                reference: url.absoluteString,
                metadata: [MetadataKeys.link: url.absoluteString]
            )
        }

        // Text copied from Teams.
        let text = object.text ?? ""
        let firstLine = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }

        return RecognizedObject(
            type: .teamsMessage,
            displayName: "Teams message",
            sourceApp: object.sourceApp ?? "teams",
            suggestedTitle: firstLine ?? "Teams: channel/chat",
            previewText: text
        )
    }
}
