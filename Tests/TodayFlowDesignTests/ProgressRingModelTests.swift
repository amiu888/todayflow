import Foundation
import Testing
@testable import TodayFlowCore
import TodayFlowDesign

/// driver.md §4 wireframe header: "◔ 5 / 9 done     4 left · 2h 10m" — the ring
/// carries the fraction; the labels carry the counts.
@Suite("ProgressRingModel")
struct ProgressRingModelTests {
    @Test("fractionAndLabels")
    func fractionAndLabels() {
        let model = ProgressRingModel(done: 5, total: 9)
        #expect(abs(model.fraction - 5.0 / 9.0) < 1e-9)
        #expect(model.doneLabel == "5 / 9 done")
        #expect(model.remainingLabel == "4 left")
        #expect(!model.isComplete)
    }

    @Test("completeWhenDoneEqualsTotal")
    func completeWhenDoneEqualsTotal() {
        let model = ProgressRingModel(done: 9, total: 9)
        #expect(model.fraction == 1)
        #expect(model.isComplete)
        #expect(model.remainingLabel == "0 left")
    }

    @Test("emptyDayIsZeroNotComplete")
    func emptyDayIsZeroNotComplete() {
        let model = ProgressRingModel(done: 0, total: 0)
        #expect(model.fraction == 0)
        #expect(!model.isComplete)
        #expect(model.doneLabel == "0 / 0 done")
        #expect(model.remainingLabel == "0 left")
    }

    @Test("overshootClampsToOne")
    func overshootClampsToOne() {
        let model = ProgressRingModel(done: 12, total: 9)
        #expect(model.fraction == 1)
        #expect(model.isComplete)
    }

    @Test("initFromRollUpResult")
    func initFromRollUpResult() {
        let result = RollUpProgress.Result(done: 3, total: 7, fraction: 3.0 / 7.0)
        let model = ProgressRingModel(result: result)
        #expect(model.done == 3)
        #expect(model.total == 7)
        #expect(abs(model.fraction - 3.0 / 7.0) < 1e-9)
        #expect(model.doneLabel == "3 / 7 done")
    }
}
