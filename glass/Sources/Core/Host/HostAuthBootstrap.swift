import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Authenticated, process-scoped Host networking context.
///
/// HTTP Remote, mux WebSocket, and downloads all receive this exact session so
/// the authority-bound browser cookie is never copied into app state.
struct AuthenticatedHostSession: @unchecked Sendable {
    let baseURL: URL
    let urlSession: URLSession

    fileprivate init(baseURL: URL, urlSession: URLSession) {
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    func invalidate() {
        urlSession.invalidateAndCancel()
    }
}

enum HostAuthBootstrapError: Error, Sendable, Equatable {
    case unexpectedStatus(Int)
    case missingRedirect
    case cookieNotEstablished
}

private final class HostBootstrapRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

enum HostAuthBootstrap {
    static func authenticate(_ descriptor: HostLaunchDescriptor) async throws -> AuthenticatedHostSession {
        let configuration = URLSessionConfiguration.ephemeral
        guard let cookieStorage = configuration.httpCookieStorage else {
            throw HostAuthBootstrapError.cookieNotEstablished
        }
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        let session = URLSession(
            configuration: configuration,
            delegate: HostBootstrapRedirectBlocker(),
            delegateQueue: nil
        )
        var authenticated = false
        defer {
            if !authenticated { session.invalidateAndCancel() }
        }
        var exchange = URLRequest(url: descriptor.launchURL)
        exchange.httpMethod = "GET"
        exchange.cachePolicy = .reloadIgnoringLocalCacheData
        exchange.setValue("no-store", forHTTPHeaderField: "Cache-Control")

        let (_, response) = try await session.data(for: exchange)
        guard let http = response as? HTTPURLResponse else {
            throw HostAuthBootstrapError.unexpectedStatus(-1)
        }
        guard http.statusCode == 303 else {
            throw HostAuthBootstrapError.unexpectedStatus(http.statusCode)
        }
        guard http.value(forHTTPHeaderField: "Location") == "/" else {
            throw HostAuthBootstrapError.missingRedirect
        }

        // URLSession normally accepts Set-Cookie before exposing the redirect.
        // Explicitly install the same response cookies as well so the bootstrap
        // semantics remain deterministic across Foundation implementations.
        var cookieHeaders: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            guard let key = key as? String, let value = value as? String else { continue }
            cookieHeaders[key] = value
        }
        let responseCookies = HTTPCookie.cookies(withResponseHeaderFields: cookieHeaders, for: descriptor.cleanBaseURL)
        if !responseCookies.isEmpty {
            cookieStorage.setCookies(responseCookies, for: descriptor.cleanBaseURL, mainDocumentURL: nil)
        }
        guard cookieStorage.cookies(for: descriptor.cleanBaseURL)?.isEmpty == false else {
            throw HostAuthBootstrapError.cookieNotEstablished
        }

        var verification = URLRequest(url: descriptor.cleanBaseURL)
        verification.httpMethod = "GET"
        verification.cachePolicy = .reloadIgnoringLocalCacheData
        let (_, verifiedResponse) = try await session.data(for: verification)
        guard let verifiedHTTP = verifiedResponse as? HTTPURLResponse,
              verifiedHTTP.statusCode == 200
        else {
            throw HostAuthBootstrapError.unexpectedStatus((verifiedResponse as? HTTPURLResponse)?.statusCode ?? -1)
        }
        authenticated = true
        return AuthenticatedHostSession(baseURL: descriptor.cleanBaseURL, urlSession: session)
    }
}
