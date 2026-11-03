import Foundation
import Testing
import TodayFlowDesign

/// The "4 left · 2h 10m" part of the header (driver.md §4): time until end of
/// business, formatted compactly.
@Suite("TimeLeft")
struct TimeLeftTests {
    @Test("nonPositiveIntervalsAreNow")
    func nonPositiveIntervalsAreNow() {
        #expect(TimeLeft.format(-5) == "now")
        #expect(TimeLeft.format(0) == "now")
    }

    @Test("roundsToNearestMinute")
    func roundsToNearestMinute() {
        #expect(TimeLeft.format(29) == "now")
        #expect(TimeLeft.format(30) == "1m")
    }

    @Test("minutesUnderAnHour")
    func minutesUnderAnHour() {
        #expect(TimeLeft.format(59 * 60) == "59m")
    }

    @Test("wholeHoursOmitMinutes")
    func wholeHoursOmitMinutes() {
        #expect(TimeLeft.format(60 * 60) == "1h")
        #expect(TimeLeft.format(360 * 60) == "6h")
    }

    @Test("hoursAndMinutes")
    func hoursAndMinutes() {
        #expect(TimeLeft.format(125 * 60) == "2h 5m")
        #expect(TimeLeft.format(150 * 60) == "2h 30m")
    }
}
