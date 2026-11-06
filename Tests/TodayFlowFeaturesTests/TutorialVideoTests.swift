import Foundation
import Testing
@testable import TodayFlowFeatures

@Suite("Tutorial video")
struct TutorialVideoTests {
    @Test func walkthroughIsBundledWithTheApp() throws {
        let url = try #require(TutorialVideoView.videoURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = try #require(attributes[.size] as? Int)
        #expect(size > 1_000_000)
    }
}
