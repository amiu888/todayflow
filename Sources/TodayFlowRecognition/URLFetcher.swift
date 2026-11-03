import Foundation

/// Fetches remote resources for the enricher (driver.md §7 step 5).
///
/// A port so tests can substitute a fake — the enricher itself never touches
/// the network directly.
public protocol URLFetcher: Sendable {
    func fetch(_ url: URL) async throws -> Data
}

/// `URLSession`-backed `URLFetcher`.
///
/// Uses `URLSession.shared` (rather than a stored session) so the struct stays
/// trivially `Sendable`; the session is shared by design.
public struct URLSessionFetcher: URLFetcher {
    public init() {}

    public func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("TodayFlow/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FetchError.notHTTPResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FetchError.status(http.statusCode)
        }
        return data
    }
}

public enum FetchError: Error, Sendable {
    case notHTTPResponse
    case status(Int)
}
