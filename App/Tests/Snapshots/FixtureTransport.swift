import DistrictNetwork
import Foundation

/// A transport that answers the app from the service's recorded responses (`contracts/`), by
/// method and path, for the screen snapshot tests.
///
/// ⚠️ A REQUEST NO RULE ANSWERS GETS A 404 ENVELOPE AND IS RECORDED, and ``ScreenSnapshotCase``
/// prints every one after a screen settles, so a screen drawn half empty because a route was
/// never mapped says which route in the log instead of looking like a real empty state.
///
/// ⚠️ IT COUNTS REQUESTS IN FLIGHT, which is what ``ScreenSnapshotCase`` waits on before it
/// takes the picture: a screen whose reads have all answered and stayed quiet has drawn what
/// it is going to draw.
final class FixtureTransport: HTTPTransport, @unchecked Sendable {
    /// What a matched request is answered with.
    enum Reply: Sendable {
        /// A file under `contracts/`, e.g. `mobile/district-calls.json`, sent as it is.
        case fixture(String)
        /// A fixture's JSON object, changed by `edit` before it is sent.
        case edited(String, @Sendable (inout [String: Any]) -> Void)
        /// A literal JSON body.
        case json(String)
        /// A status with the service's error envelope.
        case status(Int)
    }

    /// ⚠️ THE PATTERN IS KEPT AS TEXT AND COMPILED PER MATCH: a compiled `Regex` is not
    /// `Sendable`, and the rule tables are shared static values.
    struct Rule: Sendable {
        let method: HTTPMethod?
        let pattern: String
        /// The `op` a JSON body must carry, for the scheduling admin proxy, which sends every
        /// read and write to one path and names the operation in the body.
        var op: String?
        let reply: Reply
    }

    private let lock = NSLock()
    private let rules: [Rule]
    private var inFlight = 0
    private var lastActivity = Date()
    private var unanswered: [String] = []
    private var sent: [String] = []

    /// - Parameter rules: tried in order, first match wins, so a specific path goes before a
    ///   general one.
    init(rules: [Rule]) {
        self.rules = rules
    }

    /// Every `METHOD path` no rule matched, in the order they were sent.
    var unansweredRequests: [String] {
        lock.withLock { unanswered }
    }

    /// Every `METHOD path` sent, in order.
    var sentRequests: [String] {
        lock.withLock { sent }
    }

    /// True when nothing is in flight and nothing has been sent or answered for `quiet`.
    func isIdle(for quiet: TimeInterval) -> Bool {
        lock.withLock { inFlight == 0 && Date().timeIntervalSince(lastActivity) >= quiet }
    }

    func send(_ request: HTTPRequest, followRedirects _: Bool) async throws -> HTTPResponse {
        let path = request.url.path
        let op = Self.op(of: request)
        let line = "\(request.method.rawValue) \(path)" + (op.map { " op=\($0)" } ?? "")
        lock.withLock {
            inFlight += 1
            lastActivity = Date()
            sent.append(line)
        }
        defer {
            lock.withLock {
                inFlight -= 1
                lastActivity = Date()
            }
        }
        guard let rule = rules.first(where: { rule in
            (rule.method == nil || rule.method == request.method)
                && (rule.op == nil || rule.op == op)
                && path.wholeMatch(of: Self.compile(rule.pattern)) != nil
        }) else {
            lock.withLock { unanswered.append(line) }
            return Self.envelope(404, code: "not_found")
        }
        return try Self.response(rule.reply)
    }

    fileprivate static func compile(_ pattern: String) -> Regex<AnyRegexOutput> {
        // A pattern is a literal in a test file, so a typo is a programming error.
        do {
            return try Regex(pattern)
        } catch {
            preconditionFailure("not a regular expression: \(pattern) (\(error))")
        }
    }

    private static func op(of request: HTTPRequest) -> String? {
        guard let body = request.body,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return nil }
        return object["op"] as? String
    }

    private static func response(_ reply: Reply) throws -> HTTPResponse {
        switch reply {
        case let .fixture(name):
            return try ok(Fixtures.data(name))
        case let .edited(name, edit):
            var object = try Fixtures.object(name)
            edit(&object)
            return try ok(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        case let .json(body):
            return ok(Data(body.utf8))
        case let .status(code):
            return envelope(code, code: code >= 500 ? "internal_error" : "request_failed")
        }
    }

    private static func ok(_ body: Data) -> HTTPResponse {
        HTTPResponse(statusCode: 200, headers: ["Content-Type": "application/json"], body: body)
    }

    private static func envelope(_ status: Int, code: String) -> HTTPResponse {
        HTTPResponse(
            statusCode: status,
            headers: ["Content-Type": "application/json"],
            body: Data(#"{"success":false,"error":"\#(code)"}"#.utf8)
        )
    }
}

extension FixtureTransport.Rule {
    /// A rule for a path matched whole by `pattern`, a regular expression (`[^/]+` for an id).
    static func get(_ pattern: String, _ reply: FixtureTransport.Reply) -> Self {
        Self(method: .get, pattern: pattern, op: nil, reply: reply)
    }

    static func any(_ pattern: String, _ reply: FixtureTransport.Reply) -> Self {
        Self(method: nil, pattern: pattern, op: nil, reply: reply)
    }

    /// The scheduling admin proxy's `op`, answered with `reply`.
    static func scheduling(_ op: String, _ reply: FixtureTransport.Reply) -> Self {
        Self(method: .post, pattern: "/api/district/scheduling/admin", op: op, reply: reply)
    }
}

/// The contract fixtures, read from the test bundle (`contracts/` is a folder resource).
///
/// ⛔ FROM THE BUNDLE, NOT THE SOURCE TREE: the test host runs in the App Sandbox.
enum Fixtures {
    enum Missing: Error {
        case fixture(String)
    }

    static func url(_ name: String) throws -> URL {
        let root = Bundle(for: FixtureTransport.self).resourceURL?.appendingPathComponent("contracts")
        guard let file = root?.appendingPathComponent(name), FileManager.default.fileExists(atPath: file.path) else {
            throw Missing.fixture(name)
        }
        return file
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: url(name))
    }

    static func object(_ name: String) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data(name)) as? [String: Any] else {
            throw Missing.fixture(name)
        }
        return object
    }
}
