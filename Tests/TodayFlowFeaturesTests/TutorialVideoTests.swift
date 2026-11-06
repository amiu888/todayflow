import Foundation
import Testing
@testable import TodayFlowFeatures

@Suite("Tutorial video")
struct TutorialVideoTests {
    @Test func everyWalkthroughIsBundledWithTheApp() throws {
        for video in TutorialVideo.allCases {
            let url = try #require(video.url, "Missing bundled video: \(video.resourceName)")
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = try #require(attributes[.size] as? Int)
            #expect(size > 500_000, "Bundled video is unexpectedly small: \(video.resourceName)")
        }
    }
}
