import Foundation
import Testing
@testable import TodayFlowRecognition

@Suite("IcsParser")
struct IcsParserTests {
    @Test("parsesTimeZoneEvent")
    func parsesTimeZoneEvent() {
        let ics = """
            BEGIN:VCALENDAR
            VERSION:2.0
            PRODID:-//Apple Inc.//Mac OS X 10.15.0//EN
            BEGIN:VEVENT
            UID:abc-123
            SUMMARY:Design review
            DTSTART;TZID=America/New_York:20260105T103000
            DTEND;TZID=America/New_York:20260105T110000
            LOCATION:Conference room 4
            ORGANIZER;CN=Alice:mailto:alice@example.com
            URL:https://teams.microsoft.com/l/meetup-join/xyz
            END:VEVENT
            END:VCALENDAR
            """

        let event = IcsParser.parse(ics)

        #expect(event?.summary == "Design review")
        #expect(event?.location == "Conference room 4")
        #expect(event?.url == "https://teams.microsoft.com/l/meetup-join/xyz")
        #expect(IcsParser.organizerEmail(from: event?.organizer ?? "") == "alice@example.com")

        guard let start = event?.start else {
            Issue.record("start was not parsed")
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start)
        #expect(components.year == 2026)
        #expect(components.month == 1)
        #expect(components.day == 5)
        #expect(components.hour == 10)
        #expect(components.minute == 30)

        // End is 30 minutes after the start.
        #expect(event?.start != nil)
        #expect(event?.end != nil)
        #expect(event!.end!.timeIntervalSince(event!.start!) == 1800)
    }

    @Test("parsesUTCEvent")
    func parsesUTCEvent() {
        let ics = """
            BEGIN:VCALENDAR
            BEGIN:VEVENT
            SUMMARY:UTC standup
            DTSTART:20260105T090000Z
            DTEND:20260105T091500Z
            END:VEVENT
            END:VCALENDAR
            """

        let event = IcsParser.parse(ics)
        #expect(event?.summary == "UTC standup")

        guard let start = event?.start else {
            Issue.record("start was not parsed")
            return
        }
        let utc = TimeZone(identifier: "UTC")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let components = calendar.dateComponents([.hour, .minute], from: start)
        #expect(components.hour == 9)
        #expect(components.minute == 0)
        #expect(event!.end!.timeIntervalSince(event!.start!) == 900)
    }

    @Test("parsesAllDayEvent")
    func parsesAllDayEvent() {
        let ics = """
            BEGIN:VCALENDAR
            BEGIN:VEVENT
            SUMMARY:Company offsite
            DTSTART;VALUE=DATE:20260112
            DTEND;VALUE=DATE:20260113
            END:VEVENT
            END:VCALENDAR
            """

        let event = IcsParser.parse(ics)
        #expect(event?.summary == "Company offsite")
        #expect(event?.start != nil)
        #expect(event?.end != nil)

        // An all-day event spans exactly 24 hours.
        #expect(event!.end!.timeIntervalSince(event!.start!) == 86_400)
    }

    @Test("unfoldsLongLines")
    func unfoldsLongLines() {
        let ics = """
            BEGIN:VCALENDAR
            BEGIN:VEVENT
            SUMMARY: A very long summary that is folded 
             across two lines
            DTSTART:20260105T100000Z
            END:VEVENT
            END:VCALENDAR
            """

        let event = IcsParser.parse(ics)
        #expect(event?.summary == "A very long summary that is folded across two lines")
    }

    @Test("returnsNilWhenNoEvent")
    func returnsNilWhenNoEvent() {
        let ics = """
            BEGIN:VCALENDAR
            VERSION:2.0
            END:VCALENDAR
            """
        #expect(IcsParser.parse(ics) == nil)
    }

    @Test("returnsNilForGarbage")
    func returnsNilForGarbage() {
        #expect(IcsParser.parse("not an ics file") == nil)
    }
}
