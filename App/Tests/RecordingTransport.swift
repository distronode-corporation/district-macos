import DistrictNetwork
import Foundation

/// A transport that records every request and answers from a queue of canned replies.
///
/// ⚠️ AN EMPTY QUEUE THROWS rather than hanging, so code that sends a request its test
/// did not expect fails on an assertion instead of a timeout.
final class RecordingTransport: HTTPTransport, @unchecked Sendable {
    enum Failure: Error {
        case unexpectedRequest
    }

    private let lock = NSLock()
    private var replies: [Result<HTTPResponse, any Error>]
    private var recorded: [HTTPRequest] = []

    init(_ replies: [Result<HTTPResponse, any Error>] = []) {
        self.replies = replies
    }

    convenience init(status: Int, body: String = "") {
        self.init([.success(HTTPResponse(statusCode: status, body: Data(body.utf8)))])
    }

    var requests: [HTTPRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func send(_ request: HTTPRequest, followRedirects: Bool) async throws -> HTTPResponse {
        let next: Result<HTTPResponse, any Error>? = {
            lock.lock()
            defer { lock.unlock() }
            recorded.append(request)
            return replies.isEmpty ? nil : replies.removeFirst()
        }()
        guard let next else { throw Failure.unexpectedRequest }
        return try next.get()
    }

    /// The JSON object the first recorded request carried.
    func body(at index: Int = 0) throws -> [String: Any] {
        let data = try requireBody(requests[index].body)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private func requireBody(_ data: Data?) throws -> Data {
        guard let data else { throw Failure.unexpectedRequest }
        return data
    }
}
