import Foundation
import Testing
@testable import TodayFlowFeatures
import TodayFlowCore

@MainActor
struct DailyReportModelTests {
    private func makeModel() async throws -> (DailyReportModel, UserDefaults) {
        let repo = InMemoryWorkItemRepository()
        let now = Date()
        try await repo.save(WorkItem(
            title: "CHG0012345 - remove Java", status: .done, startAt: now, endAt: now,
            completedAt: now, createdAt: now, updatedAt: now
        ))
        let defaults = UserDefaults(suiteName: "dailyReport-\(UUID().uuidString)")!
        let model = DailyReportModel(repository: repo, defaults: defaults)
        await model.load()
        return (model, defaults)
    }

    @Test func loadsAndKeepsEditsUntilStartOver() async throws {
        let (model, defaults) = try await makeModel()
        #expect(model.text.contains("CHG0012345 - remove Java"))
        #expect(!model.isEdited)

        model.text += "\nExtra line"
        #expect(model.isEdited)
        model.includePriority = false
        #expect(model.text.hasSuffix("Extra line"))
        model.startOver()
        #expect(!model.isEdited)
        #expect(!model.text.contains("(P3)"))
        #expect(defaults.object(forKey: "todayflow.dailyReport.priority") as? Bool == false)
    }

    @Test func sendsTheShownText() async throws {
        let (model, _) = try await makeModel()
        var copied = ""
        var mail: (String, String)?
        var saved = ""
        model.onCopy = { copied = $0 }
        model.onEmail = { mail = ($0, $1) }
        model.onSave = { name, _ in saved = name }
        model.text = "Edited report"
        model.copy()
        model.email()
        model.markdown = true
        model.save()
        #expect(copied == "Edited report")
        #expect(mail?.0.hasPrefix("Daily report – ") == true)
        #expect(mail?.1 == "Edited report")
        #expect(saved.hasPrefix("Daily report ") && saved.hasSuffix(".md"))
    }

    @Test func cannotGoPastToday() async throws {
        let (model, _) = try await makeModel()
        let today = model.day
        model.nextDay()
        #expect(model.day == today)
        model.previousDay()
        #expect(model.day < today)
        #expect(!model.isToday)
    }
}
