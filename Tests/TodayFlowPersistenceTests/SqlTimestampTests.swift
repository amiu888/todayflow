import Foundation
import Testing
import TodayFlowPersistence

@Suite("SqlTimestamp")
struct SqlTimestampTests {
    @Test("encodes whole-second dates with millisecond precision and a Z suffix")
    func encodesWholeSecond() {
        let date = Date.whole(year: 2026, month: 1, day: 5, hour: 9, minute: 30)
        #expect(SqlTimestamp.encode(date) == "2026-01-05T09:30:00.000Z")
    }

    @Test("round-trips")
    func roundTrips() {
        let date = Date.whole(year: 2026, month: 12, day: 31, hour: 23, minute: 59, second: 59)
        #expect(SqlTimestamp.decode(SqlTimestamp.encode(date)) == date)
    }

    @Test("decodes plain second-precision strings")
    func decodesPlain() {
        let date = SqlTimestamp.decode("2026-01-05T09:30:00Z")
        #expect(date == Date.whole(year: 2026, month: 1, day: 5, hour: 9, minute: 30))
    }

    @Test("returns nil for unparseable input")
    func decodesGarbage() {
        #expect(SqlTimestamp.decode("not a date") == nil)
        #expect(SqlTimestamp.decode("") == nil)
    }

    @Test("lexicographic order equals chronological order")
    func lexicographicOrder() {
        // `Date.whole` defaults to hour 9, so give `a` a distinct hour or the
        // two encodings would be identical.
        let a = Date.whole(year: 2026, month: 1, day: 5, hour: 8)
        let b = Date.whole(year: 2026, month: 1, day: 5, hour: 9)
        let c = Date.whole(year: 2026, month: 2, day: 1)
        let ea = SqlTimestamp.encode(a)
        let eb = SqlTimestamp.encode(b)
        let ec = SqlTimestamp.encode(c)
        #expect(ea < eb)
        #expect(eb < ec)
    }
}
