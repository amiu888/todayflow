import Testing
@testable import TodayFlowCore

@Suite("Tag names")
struct TagNameTests {
    @Test func parsesCommaAndSemicolonSeparatedTags() {
        #expect(
            TagName.parse(" launch, Q4; launch ,, ops ")
                == ["launch", "Q4", "ops"]
        )
    }

    @Test func trimsAndCapsVeryLongTags() {
        let long = String(repeating: "a", count: 80)
        let tags = TagName.normalize(["  \(long)  "])
        #expect(tags.count == 1)
        #expect(tags[0].count == TagName.maximumLength)
    }

    @Test func turnsWhitespaceIntoPortableHyphens() {
        #expect(TagName.normalize(["Client A"]) == ["Client-A"])
    }

    @Test func capsTheNumberOfTags() {
        let many = (1...20).map { "tag\($0)" }
        #expect(TagName.normalize(many).count == TagName.maximumCount)
    }

    @Test func buildsACompactDisplayString() {
        #expect(TagName.display(["launch", "Q4", "ops"]) == "#launch #Q4 +1")
        #expect(TagName.display(["launch"]) == "#launch")
    }
}
