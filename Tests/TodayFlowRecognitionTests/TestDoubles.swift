import Foundation
import TodayFlowRecognition

/// A recording `FileAccess` for materializer tests — it never touches the disk.
final class FakeFileAccess: FileAccess, @unchecked Sendable {
    struct Copy: Equatable {
        let from: URL
        let to: URL
    }

    struct Write: Equatable {
        let data: Data
        let to: URL
    }

    struct FakeError: Error {}

    let fail: Bool
    let bookmarkData: Data?

    init(fail: Bool = false, bookmarkData: Data? = Data([0x42])) {
        self.fail = fail
        self.bookmarkData = bookmarkData
    }

    private let lock = NSLock()
    private var _createdDirectories: [URL] = []
    private var _copies: [Copy] = []
    private var _writes: [Write] = []
    private var _bookmarkRequests: [URL] = []

    var createdDirectories: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return _createdDirectories
    }

    var copies: [Copy] {
        lock.lock()
        defer { lock.unlock() }
        return _copies
    }

    var writes: [Write] {
        lock.lock()
        defer { lock.unlock() }
        return _writes
    }

    var bookmarkRequests: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return _bookmarkRequests
    }

    func isDirectory(_ url: URL) -> Bool? { nil }
    func size(of url: URL) -> Int64? { nil }
    func modificationDate(of url: URL) -> Date? { nil }

    func copy(from source: URL, to destination: URL) throws {
        if fail { throw FakeError() }
        lock.lock()
        _copies.append(Copy(from: source, to: destination))
        lock.unlock()
    }

    func write(_ data: Data, to url: URL) throws {
        if fail { throw FakeError() }
        lock.lock()
        _writes.append(Write(data: data, to: url))
        lock.unlock()
    }

    func securityScopedBookmark(for url: URL) -> Data? {
        lock.lock()
        _bookmarkRequests.append(url)
        lock.unlock()
        return fail ? nil : bookmarkData
    }

    func url(fromSecurityScopedBookmark data: Data) -> URL? { nil }

    func createDirectory(_ url: URL) throws {
        if fail { throw FakeError() }
        lock.lock()
        _createdDirectories.append(url)
        lock.unlock()
    }
}

/// A `URLFetcher` double with a fixed behavior, recording every request.
final class FakeFetcher: URLFetcher, @unchecked Sendable {
    enum Behavior {
        case data(Data)
        case failure
    }

    let behavior: Behavior

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    private let lock = NSLock()
    private var _fetches: [URL] = []

    var fetches: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return _fetches
    }

    func fetch(_ url: URL) async throws -> Data {
        recordFetch(url)
        switch behavior {
        case .data(let data):
            return data
        case .failure:
            throw FetchError.status(500)
        }
    }

    private func recordFetch(_ url: URL) {
        lock.lock()
        _fetches.append(url)
        lock.unlock()
    }
}
