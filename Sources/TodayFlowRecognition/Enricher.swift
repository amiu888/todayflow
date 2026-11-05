import Foundation
import TodayFlowCore

/// Fills in the slow parts of a `CaptureDraft` after the sheet has opened
/// (driver.md §7 step 5): URL page titles, and (later) PDF/Office text and
/// thumbnails.
///
/// The enricher is async but never throws: a failed fetch simply leaves the
/// object unchanged, so the sheet's live updates degrade gracefully
/// (driver.md §8: AI and enrichment are optional).
public struct Enricher: Sendable {
    public var fetcher: any URLFetcher

    public init(fetcher: any URLFetcher) {
        self.fetcher = fetcher
    }

    /// Returns the draft with whatever could be enriched in place.
    public func enrich(_ draft: CaptureDraft) async -> CaptureDraft {
        var result = draft
        for index in result.objects.indices {
            guard result.objects[index].type == .url,
                  result.objects[index].metadata[MetadataKeys.jiraIssueKey] == nil,
                  let reference = result.objects[index].reference,
                  let url = URL(string: reference),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https"
            else { continue }

            // PDF/Office text extraction (PDFKit / NSAttributedString) and
            // thumbnails (QuickLookThumbnailing) are added here in a later
            // increment; they are platform-framework work and stay out of the
            // drop path.

            guard let data = try? await fetcher.fetch(url) else { continue }
            guard let title = Self.htmlTitle(data) else { continue }

            result.objects[index].suggestedTitle = title
            result.objects[index].displayName = title
            result.objects[index].metadata[MetadataKeys.pageTitle] = title
        }
        return result
    }

    /// Extracts the `<title>` of an HTML document (case-insensitive, with
    /// common entity unescaping). Returns `nil` when there is no title.
    static func htmlTitle(_ data: Data) -> String? {
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        guard let open = text.range(of: "<title>", options: .caseInsensitive) else {
            return nil
        }
        guard let close = text.range(of: "</title>", options: .caseInsensitive, range: open.upperBound..<text.endIndex)
        else { return nil }
        let raw = text[open.upperBound..<close.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let unescaped = unescapeHTML(raw)
        return unescaped.isEmpty ? nil : unescaped
    }

    /// Unescapes the common HTML entities.
    static func unescapeHTML(_ text: String) -> String {
        var result = text
        let named: [String: String] = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&nbsp;": " ",
        ]
        for (entity, character) in named {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        // Numeric entities: &#39; and &#x27;
        if let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result),
                      let hexRange = Range(match.range(at: 1), in: result),
                      let digitRange = Range(match.range(at: 2), in: result)
                else { continue }
                let isHex = result[hexRange] == "x"
                let digits = String(result[digitRange])
                let radix = isHex ? 16 : 10
                if let value = UInt32(digits, radix: radix),
                   let scalar = Unicode.Scalar(value)
                {
                    result.replaceSubrange(range, with: String(scalar))
                }
            }
        }
        return result
    }
}
