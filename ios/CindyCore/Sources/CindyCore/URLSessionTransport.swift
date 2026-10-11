import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The real `HttpTransport`, over `URLSession`. Every Strava endpoint is `https`, and a request to
/// anything else is refused rather than sent.
///
/// It never logs a header or a body: the bearer token lives in a header, and both the OAuth token
/// exchange and the athlete's activity data live in bodies. A stack trace from here must be as safe
/// to paste into a bug report as one from anywhere else in the app.
///
/// A redirect is never followed. It would re-send the bearer token, or the athlete's upload, to a
/// host this code did not choose, and a POST is quietly turned into a GET on the way. A 3xx comes
/// back as an ordinary response for the caller to refuse.
///
/// Two differences from Android's `HttpsURLConnection`, both `URLSession`'s: there is one timeout
/// for a request that goes quiet (30 s, Android's read timeout) and none for connecting alone
/// (Android's 15 s), and a header the server sent more than once arrives as one comma-joined value.
public final class URLSessionTransport: HttpTransport, @unchecked Sendable {

    private let session: URLSession
    private let readTimeout: TimeInterval

    /// `configuration` is for tests, which swap in a stub protocol, and for a caller that needs its
    /// own settings. The default keeps nothing: no cookies, no cache, no stored credentials.
    public init(readTimeout: TimeInterval = 30, configuration: URLSessionConfiguration? = nil) {
        let config = configuration ?? {
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false
            config.httpCookieStorage = nil
            config.urlCache = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            return config
        }()
        config.timeoutIntervalForRequest = readTimeout
        self.readTimeout = readTimeout
        self.session = URLSession(configuration: config, delegate: RefuseRedirects(), delegateQueue: nil)
    }

    public func execute(_ request: HttpRequest) async throws -> HttpResponse {
        guard let url = URL(string: request.url), url.scheme == "https" else {
            throw HttpTransportError("Only https requests are sent")
        }
        var urlRequest = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: readTimeout)
        urlRequest.httpMethod = request.method
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        if let contentType = request.contentType { urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        urlRequest.httpBody = request.body

        let (data, response) = try await load(urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw HttpTransportError("The reply was not HTTP")
        }
        var headers: [String: [String]] = [:]
        for (name, value) in http.allHeaderFields {
            if let name = name as? String { headers[name] = [String(describing: value)] }
        }
        return HttpResponse(http.statusCode, headers, String(decoding: data, as: UTF8.self))
    }

    /// Hands a request to the session and waits for its answer. A task that is cancelled while it
    /// waits cancels the request with it.
    private func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let holder = TaskHolder()
        do {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    let task = session.dataTask(with: request) { data, response, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else if let response = response {
                            continuation.resume(returning: (data ?? Data(), response))
                        } else {
                            continuation.resume(throwing: URLError(.badServerResponse))
                        }
                    }
                    holder.set(task)
                    task.resume()
                }
            } onCancel: {
                holder.cancel()
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            // Every way a `URLSession` call fails is the network's: no connection, a timeout, a
            // reset, a certificate that does not check out.
            throw HttpTransportError(error.localizedDescription)
        }
    }
}

/// Says no to every redirect, so the 3xx itself is the answer.
final class RefuseRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// The running task, so the cancellation handler (which runs on another thread) can reach it.
private final class TaskHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var cancelled = false

    func set(_ task: URLSessionTask) {
        lock.lock()
        defer { lock.unlock() }
        self.task = task
        if cancelled { task.cancel() }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        task?.cancel()
    }
}
