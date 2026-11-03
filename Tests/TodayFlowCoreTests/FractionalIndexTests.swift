import Foundation
import Testing
@testable import TodayFlowCore

struct FractionalIndexTests {
    @Test func bottomIsSmallest() {
        #expect(FractionalIndex.isLessThan(FractionalIndex.bottom, "1"))
        #expect(FractionalIndex.isLessThan("0", "1"))
    }

    @Test func midpointOfNoBoundsIsHalf() {
        // 0.5 in base-62 is the single digit of code 31 → 'V'.
        #expect(FractionalIndex.midpoint(nil, nil) == "V")
    }

    @Test func midpointIsStrictlyBetween() {
        let mid = FractionalIndex.midpoint("1", "9")
        #expect(FractionalIndex.isLessThan("1", mid))
        #expect(FractionalIndex.isLessThan(mid, "9"))
    }

    @Test func midpointBeforeFirst() {
        let mid = FractionalIndex.midpoint(nil, "1")
        #expect(FractionalIndex.isLessThan(mid, "1"))
        #expect(FractionalIndex.isLessThan(mid, "9"))
    }

    @Test func midpointAfterLast() {
        let mid = FractionalIndex.midpoint("9", nil)
        #expect(FractionalIndex.isLessThan("9", mid))
        #expect(!mid.isEmpty)
    }

    @Test func byteOrderMatchesAlphabet() {
        // digits < uppercase < lowercase, matching SQLite's BINARY collation.
        #expect(FractionalIndex.isLessThan("9", "A"))
        #expect(FractionalIndex.isLessThan("Z", "a"))
    }

    @Test func prefixSortsFirst() {
        #expect(FractionalIndex.isLessThan("1", "10"))
    }

    @Test func codeAndCharRoundTrip() {
        for (i, c) in FractionalIndex.alphabet.enumerated() {
            #expect(FractionalIndex.code(c) == i)
            #expect(FractionalIndex.char(i) == c)
        }
        // Out-of-range codes clamp to '0'.
        #expect(FractionalIndex.char(62) == "0")
        #expect(FractionalIndex.char(-1) == "0")
    }

    @Test func repeatedMidpointsStayStrictlyOrdered() {
        // Repeatedly bisect the same slot; the list must remain strictly ordered.
        var keys = ["1", "9"]
        for _ in 0..<50 {
            keys.insert(FractionalIndex.midpoint(keys[0], keys[1]), at: 1)
        }
        for i in 1..<keys.count {
            #expect(FractionalIndex.isLessThan(keys[i - 1], keys[i]))
        }
    }
}
