import Foundation
import Testing
@testable import TodayFlowCore

struct UUIDv7Tests {
    @Test func timestampRoundTrip() {
        let ts: Int64 = 1_700_000_000_123
        let id = UUIDv7(timestampMilliseconds: ts)
        #expect(id.timestampMilliseconds == ts)
    }

    @Test func timestampAsDate() {
        let id = UUIDv7(timestampMilliseconds: 1_700_000_000_000)
        #expect(abs(id.timestamp.timeIntervalSince1970 - 1_700_000_000.0) < 0.001)
    }

    @Test func orderingFollowsTimestamp() {
        let a = UUIDv7(timestampMilliseconds: 1_000)
        let b = UUIDv7(timestampMilliseconds: 2_000)
        #expect(a < b)
        #expect(!(b < a))
    }

    @Test func versionNibbleIsSeven() {
        let id = UUIDv7(timestampMilliseconds: 1_000)
        #expect((id.uuid.uuid.6 >> 4) == 7)
    }

    @Test func codableRoundTrip() throws {
        let id = UUIDv7(timestampMilliseconds: 1_700_000_000_123)
        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(UUIDv7.self, from: data)
        #expect(decoded == id)
        #expect(decoded.timestampMilliseconds == id.timestampMilliseconds)
    }

    @Test func newIsUnique() {
        let a = UUIDv7.new()
        let b = UUIDv7.new()
        #expect(a.uuid != b.uuid)
    }
}
