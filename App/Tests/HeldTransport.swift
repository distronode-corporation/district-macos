import DistrictNetwork
import Foundation

/// A transport that holds its FIRST request until ``release()``, then answers from a queue.
///
/// ⛔ FOR SINGLE-FLIGHT TESTS THAT PROVE AN OVERLAP. Two `async let` calls may run one after
/// the other and pass with no guard at all; holding the first request on the wire makes the
/// second call start while the first is provably in flight (cubic on #111).
final class HeldTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [HTTPResponse]
    private var requests: [HTTPRequest] = []
    private var held: CheckedContinuation<Void, Never>?
    private var released = false

    init(responses: [(status: Int, body: String)]) {
        self.responses = responses.map {
            HTTPResponse(statusCode: $0.status, headers: ["Content-Type": "application/json"], body: Data($0.body.utf8))
        }
    }

    var requestCount: Int {
        lock.withLock { requests.count }
    }

    var paths: [String] {
        lock.withLock { requests }.map(\.url.path)
    }

    /// Lets the held request through. ⚠️ Safe before the request arrives: it is then not held.
    func release() {
        let waiting: CheckedContinuation<Void, Never>? = lock.withLock {
            released = true
            defer { held = nil }
            return held
        }
        waiting?.resume()
    }

    func send(_ request: HTTPRequest, followRedirects: Bool) async throws -> HTTPResponse {
        _ = followRedirects
        let first: Bool = lock.withLock {
            requests.append(request)
            return requests.count == 1
        }
        if first {
            await withCheckedContinuation { continuation in
                let resumeNow: Bool = lock.withLock {
                    if released {
                        return true
                    }
                    held = continuation
                    return false
                }
                if resumeNow {
                    continuation.resume()
                }
            }
        }
        let next: HTTPResponse? = lock.withLock { responses.isEmpty ? nil : responses.removeFirst() }
        return next ?? HTTPResponse(statusCode: 500, headers: [:], body: nil)
    }
}
