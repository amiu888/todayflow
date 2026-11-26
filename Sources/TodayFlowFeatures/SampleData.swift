import Foundation
import TodayFlowCore

/// Sample tasks for screenshots, tutorial recordings and first tests, on the
/// Mac and the iPhone: launch with `-seedSample`.
/// Only seeds an empty database, so it never touches real data.
public enum SampleData {
    public static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedSample")
    }

    @MainActor
    public static func seedIfRequested(workItems: any WorkItemRepository, calendar workCalendar: WorkCalendar) async {
        guard isRequested else { return }
        guard await workItems.allItems().isEmpty else { return }
        let create = CreateTask(repository: workItems, calendar: workCalendar)
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
        let samples: [(String, Int, Int, Priority, [String], Bool, String)] = [
            ("Sign vendor contract", -1, 16, .urgent, ["legal"], false, "Legal approved the last redline. Needs a signature from finance too."),
            ("Reply to Maria about the launch", 0, 0, .high, [], false, ""),
            ("Review Q4 roadmap", 0, 1, .high, ["Q4"], true, "Check the dates against the partner calendar before Friday."),
            ("Call supplier", 0, 2, .normal, [], false, ""),
            ("Budget draft", 0, 3, .normal, ["Q4"], true, ""),
            ("Book flights to Lisbon", 0, 4, .low, ["travel"], false, ""),
            ("Team retro notes", 1, 10, .normal, [], true, ""),
            ("Quarterly report", 3, 16, .high, ["Q4"], true, ""),
        ]
        for (title, day, hour, priority, tags, inProject, notes) in samples {
            let due = at(day, hour)
            _ = try? await create.execute(.init(
                title: title,
                descriptionMd: notes,
                parentId: inProject ? project?.id : nil,
                startAt: due.addingTimeInterval(-3600),
                endAt: due,
                priority: priority,
                tags: tags
            ))
        }
    }
}
