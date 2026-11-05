import Foundation
import TodayFlowCore

/// Prompt templates live as versioned resources in this package (driver.md §8:
/// "prompt templates are versioned files in the package, not string literals in
/// views"). Bump the filename version when the output contract changes.
struct PromptLibrary: Sendable {
    static let suggest = "suggest_v1"
    static let breakDown = "break_down_v1"
    static let planDay = "plan_day_v1"
    static let ask = "ask_v1"

    func text(_ name: String) -> String {
        if let url = Bundle.module.url(forResource: name, withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8)
        {
            return text
        }
        return "Return only valid JSON for the requested task."
    }

    func render(_ name: String, _ values: [String: String]) -> String {
        var result = text(name)
        for (key, value) in values {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return result
    }
}

/// Compact, privacy-aware text forms of the data sent to the model.
enum PromptContext {
    static func objects(_ objects: [RecognizedObject], includeText: Bool) -> String {
        objects.map { object in
            var lines = [
                "- type: \(object.type.rawValue)",
                "  name: \(object.displayName)",
            ]
            if let uti = object.uti { lines.append("  uti: \(uti)") }
            if let source = object.sourceApp { lines.append("  source: \(source)") }
            if let suggestion = object.suggestedTitle {
                lines.append("  suggested title: \(suggestion)")
            }
            if includeText, let preview = object.previewText, !preview.isEmpty {
                lines.append("  text: \(preview.prefix(2_000))")
            }
            if includeText, !object.metadata.isEmpty {
                let metadata = object.metadata
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: ", ")
                lines.append("  metadata: \(metadata)")
            }
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n")
    }

    static func task(_ item: WorkItem, includeDescription: Bool) -> String {
        var lines = [
            "- id: \(item.id)",
            "  title: \(item.title)",
            "  status: \(item.status.rawValue)",
            "  priority: \(item.priority.label)",
            "  due: \(ISO8601DateFormatter().string(from: item.endAt))",
        ]
        if includeDescription, !item.descriptionMd.isEmpty {
            lines.append("  description: \(item.descriptionMd.prefix(2_000))")
        }
        return lines.joined(separator: "\n")
    }

    static func tasks(_ items: [WorkItem], includeDescription: Bool = false) -> String {
        items.map { task($0, includeDescription: includeDescription) }
            .joined(separator: "\n")
    }

    static func hours(_ calendar: WorkCalendar) -> String {
        String(
            format: "%02d:00–%02d:00, working days %@",
            Int(calendar.startHour),
            Int(calendar.endHour),
            weekdayList(calendar.workWeekdays)
        )
    }

    private static func weekdayList(_ weekdays: Set<Int>) -> String {
        let names = [1: "Sun", 2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat"]
        return weekdays.sorted().compactMap { names[$0] }.joined(separator: ", ")
    }
}
