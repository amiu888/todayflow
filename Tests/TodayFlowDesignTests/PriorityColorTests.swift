import SwiftUI
import Testing
import TodayFlowCore
import TodayFlowDesign

/// driver.md §4 row spec: "priority dot (P1 red, P2 orange, P3 yellow, P4 grey)".
///
/// The scale is a *status* scale (see `PriorityColor` for the validation notes):
/// the three colored steps are the data-viz reference palette's fixed status
/// steps; only P4 (neutral) steps per color scheme.
@Suite("PriorityColor")
struct PriorityColorTests {
    @Test("urgentIsCriticalRedInBothSchemes")
    func urgentIsCriticalRedInBothSchemes() {
        #expect(PriorityColor.hex(for: .urgent, in: .light) == "#d03b3b")
        #expect(PriorityColor.hex(for: .urgent, in: .dark) == "#d03b3b")
    }

    @Test("highIsSeriousOrangeInBothSchemes")
    func highIsSeriousOrangeInBothSchemes() {
        #expect(PriorityColor.hex(for: .high, in: .light) == "#ec835a")
        #expect(PriorityColor.hex(for: .high, in: .dark) == "#ec835a")
    }

    @Test("normalIsWarningYellowInBothSchemes")
    func normalIsWarningYellowInBothSchemes() {
        #expect(PriorityColor.hex(for: .normal, in: .light) == "#fab219")
        #expect(PriorityColor.hex(for: .normal, in: .dark) == "#fab219")
    }

    @Test("lowIsNeutralGraySteppedPerScheme")
    func lowIsNeutralGraySteppedPerScheme() {
        #expect(PriorityColor.hex(for: .low, in: .light) == "#8e8e93")
        #expect(PriorityColor.hex(for: .low, in: .dark) == "#98989d")
    }

    @Test("allFourResolveToDistinctColors")
    func allFourResolveToDistinctColors() {
        let environment = EnvironmentValues()
        let components = Priority.allCases.map { priority -> (Float, Float, Float) in
            let resolved = PriorityColor.color(for: priority, in: .light).resolve(in: environment)
            return (resolved.red, resolved.green, resolved.blue)
        }
        for index in components.indices {
            for other in components.indices where index != other {
                #expect(components[index] != components[other])
            }
        }
    }
}
