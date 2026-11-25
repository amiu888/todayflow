#if os(iOS)
import Foundation
import TodayFlowCore

/// Sample tasks for screenshots and first tests: launch with `-seedSample`.
/// Only seeds an empty database, so it never touches real data.
enum PhoneSampleData {
    @MainActor
    static func seedIfRequested(_ environment: PhoneEnvironment) async {
        guard ProcessInfo.processInfo.arguments.contains("-seedSample") else { return }
        guard await environment.workItems.allItems().isEmpty else { return }
        let create = CreateTask(repository: environment.workItems, calendar: environment.workCalendar)
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func at(_ dayOffset: Int, _ hour: Int) -> Date {
            cal.date(byAdding: .day, value: dayOffset, to: today)!.addingTimeInterval(Double(hour) * 3600)
        }
        let project = try? await create.execute(.init(kind: .project, title: "Launch Q4", color: "#7c6cf2"))
        let samples: [(String, Int, Int, Priority, [String], Bool)] = [
            ("Vendor contract", -3, 9, .urgent, ["legal"], false),
            ("Call supplier", -1, 9, .normal, [], false),
            ("Review Q4 roadmap", 0, 17, .high, ["Q4"], true),
            ("Budget draft", 0, 18, .normal, ["Q4"], true),
            ("Reply to Maria", 0, 11, .high, [], false),
            ("Book flights", 0, 14, .low, ["travel"], false),
            ("Team retro notes", 1, 10, .normal, [], true),
            ("Quarterly report", 3, 16, .high, ["Q4"], true),
        ]
        for (title, day, hour, priority, tags, inProject) in samples {
            let due = at(day, hour)
            _ = try? await create.execute(.init(
                title: title,
                parentId: inProject ? project?.id : nil,
                startAt: due.addingTimeInterval(-3600),
                endAt: due,
                priority: priority,
                tags: tags
            ))
        }
    }
}
#endif
