import Foundation
import Testing
import TodayFlowCore
@testable import TodayFlowRecognition

@Suite("Enricher")
struct EnricherTests {
    private static let page = Data(
        "<html><head><TITLE>Example Article</TITLE></head><body>hi</body></html>".utf8
    )

    private static let urlObject = RecognizedObject(
        type: .url,
        displayName: "example.com",
        reference: "https://example.com/article"
    )

    @Test("fillsUrlTitleFromFetchedHtml")
    func fillsUrlTitleFromFetchedHtml() async {
        let fetcher = FakeFetcher(behavior: .data(Self.page))
        let enricher = Enricher(fetcher: fetcher)
        let draft = CaptureDraft(title: "example.com", objects: [Self.urlObject])

        let result = await enricher.enrich(draft)

        #expect(result.objects[0].suggestedTitle == "Example Article")
        #expect(result.objects[0].displayName == "Example Article")
        #expect(result.objects[0].metadata[MetadataKeys.pageTitle] == "Example Article")
        #expect(fetcher.fetches == [URL(string: "https://example.com/article")!])
    }

    @Test("fetchFailureLeavesDraftUnchanged")
    func fetchFailureLeavesDraftUnchanged() async {
        let fetcher = FakeFetcher(behavior: .failure)
        let enricher = Enricher(fetcher: fetcher)
        let draft = CaptureDraft(title: "example.com", objects: [Self.urlObject])

        let result = await enricher.enrich(draft)

        #expect(result == draft)
        #expect(fetcher.fetches.count == 1)
    }

    @Test("nonUrlObjectsAreNotFetched")
    func nonUrlObjectsAreNotFetched() async {
        let fetcher = FakeFetcher(behavior: .data(Self.page))
        let enricher = Enricher(fetcher: fetcher)
        let draft = CaptureDraft(
            title: "Invoice",
            objects: [RecognizedObject(type: .file, displayName: "Invoice.pdf", reference: "/tmp/Invoice.pdf")]
        )

        let result = await enricher.enrich(draft)

        #expect(result == draft)
        #expect(fetcher.fetches.isEmpty)
    }

    @Test("unparseableReferenceIsNotFetched")
    func unparseableReferenceIsNotFetched() async {
        let fetcher = FakeFetcher(behavior: .data(Self.page))
        let enricher = Enricher(fetcher: fetcher)
        let draft = CaptureDraft(
            title: "t",
            objects: [RecognizedObject(type: .url, displayName: "example.com", reference: "not a url")]
        )

        let result = await enricher.enrich(draft)

        #expect(result == draft)
        #expect(fetcher.fetches.isEmpty)
    }

    @Test("htmlTitleExtraction")
    func htmlTitleExtraction() {
        #expect(Enricher.htmlTitle(Data("<html><title>  Hello World  </title></html>".utf8)) == "Hello World")
        #expect(Enricher.htmlTitle(Data("<html><head><TiTlE>Mixed Case</TiTlE></head></html>".utf8)) == "Mixed Case")
        #expect(Enricher.htmlTitle(Data("<html><body>no title here</body></html>".utf8)) == nil)
        #expect(Enricher.htmlTitle(Data("<html><title>a &amp; b &#x27;c&#39;</title></html>".utf8)) == "a & b 'c'")
        #expect(Enricher.htmlTitle(Data("not html at all".utf8)) == nil)
    }
}
