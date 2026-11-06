import Testing
@testable import TodayFlowFeatures

@Suite("Today section collapse policy")
struct TodaySectionCollapsePolicyTests {
    @Test func aFullHeightPanelKeepsEverySectionOpen() {
        let sections = TodaySectionCollapsePolicy.autoCollapsed(
            forHeight: 668,
            hasDone: true,
            hasUpcoming: true,
            hasOverdue: true
        )
        #expect(sections.isEmpty)
    }

    @Test func sectionsFoldFromTheBottomAsHeightShrinks() {
        let height620 = TodaySectionCollapsePolicy.autoCollapsed(
            forHeight: 619,
            hasDone: true,
            hasUpcoming: true,
            hasOverdue: true
        )
        #expect(height620 == [.done])

        let height560 = TodaySectionCollapsePolicy.autoCollapsed(
            forHeight: 559,
            hasDone: true,
            hasUpcoming: true,
            hasOverdue: true
        )
        #expect(height560 == [.done, .upcoming])

        let height500 = TodaySectionCollapsePolicy.autoCollapsed(
            forHeight: 499,
            hasDone: true,
            hasUpcoming: true,
            hasOverdue: true
        )
        #expect(height500 == [.done, .upcoming, .trays])
    }

    @Test func topSectionsFoldBeforeTheUrgentOverdueList() {
        let height450 = TodaySectionCollapsePolicy.autoCollapsed(
            forHeight: 449,
            hasDone: true,
            hasUpcoming: true,
            hasOverdue: true
        )
        #expect(height450 == [.done, .upcoming, .trays, .week])
        #expect(!height450.contains(.overdue))
        #expect(!height450.contains(.today))
    }

    @Test func overdueStaysVisibleAtTheMinimumHeight() {
        let sections = TodaySectionCollapsePolicy.autoCollapsed(
            forHeight: 420,
            hasDone: true,
            hasUpcoming: true,
            hasOverdue: true
        )
        #expect(sections == [.done, .upcoming, .trays, .week])
        #expect(!sections.contains(.overdue))
        #expect(!sections.contains(.today))
    }

    @Test func onlySectionsWithContentAreFolded() {
        let sections = TodaySectionCollapsePolicy.autoCollapsed(
            forHeight: 400,
            hasDone: false,
            hasUpcoming: false,
            hasOverdue: false
        )
        #expect(sections == [.trays, .week])
    }

    @Test func theOpenTaskListIsNeverFoldedAutomatically() {
        for height in stride(from: 300.0, through: 800.0, by: 20.0) {
            let sections = TodaySectionCollapsePolicy.autoCollapsed(
                forHeight: height,
                hasDone: true,
                hasUpcoming: true,
                hasOverdue: true
            )
            #expect(!sections.contains(.today))
        }
    }
}
