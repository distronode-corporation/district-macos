import DistrictNetwork
import Foundation

/// The one concrete ``HTTPTransport``: Darwin `URLSession`.
///
/// Ported from district-ios unchanged. ⛔ IT LIVES IN THE APP AND NOT IN THE SHARED
/// CORE: `URLSession` on Linux is libcurl-backed and differs from Darwin's in redirect
/// handling, header casing and error domains, so the core's Linux tests could neither
/// exercise this file nor trust what they measured.
///
/// ⚠️ NOTHING HERE IS COVERED BY A UNIT TEST. Keep it boring: no retry policy, no
/// caching cleverness, no error re-mapping beyond what the protocol asks for.
final class URLSessionHTTPTransport: NSObject, HTTPTransport, URLSessionTaskDelegate, @unchecked Sendable {
    /// ⚠️ Applied to the REQUEST, not the whole resource, so a slow media upload is not
    /// capped by it.
    private static let requestTimeout: TimeInterval = 30

    private let session: URLSession

    init(configuration: URLSessionConfiguration = .default) {
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        // ⛔ NO COOKIES ON THE API PATH. Every request is authorised by a bearer token;
        // a cookie jar would be a second, ambient credential.
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        session = URLSession(configuration: configuration)
        super.init()
    }

    func send(_ request: HTTPRequest, followRedirects: Bool) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        // ⛔ THE DELEGATE IS THE WHOLE REDIRECT POLICY, attached per task so refusing a
        // redirect (the scheduler hand-off's `Location`) never applies to other calls.
        let (data, response) = try await session.data(
            for: urlRequest,
            delegate: followRedirects ? nil : self
        )

        guard let http = response as? HTTPURLResponse else {
            throw URLSessionHTTPTransportError.notAnHTTPResponse
        }

        return HTTPResponse(
            statusCode: http.statusCode,
            headers: Self.headers(from: http),
            body: data
        )
    }

    /// Refuses every redirect for a task this object is the delegate of; the 3xx is
    /// returned to the caller as-is.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    private static func headers(from response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (name, value) in response.allHeaderFields {
            guard let name = name as? String, let value = value as? String else { continue }
            headers[name] = value
        }
        return headers
    }
}

enum URLSessionHTTPTransportError: Error {
    case notAnHTTPResponse
}
