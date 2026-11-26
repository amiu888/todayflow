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
        // Today's tasks fall in the hours after "now", so screenshots look like
        // a normal working day whenever they are taken.
        let nextHour = cal.dateInterval(of: .hour, for: .now)!.end
        func at(_ dayOffset: Int, _ hour: Int) -> Date {
            if dayOffset == 0 { return nextHour.addingTimeInterval(Double(hour) * 3600) }
            return cal.date(byAdding: .day, value: dayOffset, to: today)!.addingTimeInterval(Double(hour) * 3600)
        }
        let project = try? await create.execute(.init(kind: .project, title: "Launch Q4", color: "#7c6cf2"))
        // Today entries: hours after the next full hour. Other days: hour of day.
        let samples: [(String, Int, Int, Priority, [String], Bool)] = [
            ("Sign vendor contract", -1, 16, .urgent, ["legal"], false),
            ("Reply to Maria about the launch", 0, 0, .high, [], false),
            ("Review Q4 roadmap", 0, 1, .high, ["Q4"], true),
            ("Call supplier", 0, 2, .normal, [], false),
            ("Budget draft", 0, 3, .normal, ["Q4"], true),
            ("Book flights to Lisbon", 0, 4, .low, ["travel"], false),
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
