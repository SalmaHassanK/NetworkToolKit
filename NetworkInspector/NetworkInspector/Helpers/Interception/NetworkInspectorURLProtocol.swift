//
//  NetworkInspectorURLProtocol.swift
//  NetworkInspector
//
//  URLProtocol-based transport interceptor. Reads the lifecycle context
//  attached to the request as a URLProtocol property (never serialized to
//  the wire) and records the request lifecycle without relying on a wrapper
//  URLSession delegate.
//

import Foundation

public final class NetworkInspectorURLProtocol: URLProtocol {
    private static let handledKey = "NetworkInspectorURLProtocolHandled"

    /// One internal session shared by every intercepted request. A
    /// per-request session would give each request its own connection pool —
    /// no keep-alive or TLS session reuse, so every request pays a fresh
    /// handshake — and would leak, because URLSession retains its delegate
    /// until invalidated. The shared delegate routes callbacks back to the
    /// owning protocol instance by task identifier.
    private static let sessionDelegate = MultiplexingSessionDelegate()
    private static let sharedSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = (configuration.protocolClasses ?? [])
            .filter { $0 != NetworkInspectorURLProtocol.self }
        return URLSession(
            configuration: configuration,
            delegate: sessionDelegate,
            delegateQueue: nil
        )
    }()

    private var dataTask: URLSessionDataTask?
    private var response: URLResponse?
    private var receivedData = Data()
    private var lifecycle: InspectedChain?
    private var forwardedDelegate: URLSessionDelegate?
    private var decryptor: AttemptDecryptor?

    // Note: this deliberately keys on the attached context rather than on
    // `NetworkInspector.shared.isEnabled` — while disabled, no request is
    // ever instrumented (see `networkInspectorDataTask`), so nothing matches
    // here. The context is a URLProtocol property, so an unintercepted
    // request leaks nothing to the wire either way.
    public override class func canInit(with request: URLRequest) -> Bool {
        guard URLProtocol.property(forKey: handledKey, in: request) as? Bool != true else {
            return false
        }

        return NetworkInspectorRequestContext.context(for: request) != nil
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    public override func startLoading() {
        let sanitizedRequest = sanitizedInterceptedRequest(from: request)

        if let context = NetworkInspectorRequestContext.context(for: request) {
            lifecycle = context.lifecycle
            forwardedDelegate = context.forwardedDelegate
            decryptor = context.decryptor
            beginLifecycle(
                context.lifecycle,
                kind: context.kind,
                // Snapshot captured before the request entered the URL loading
                // system — inside the protocol `httpBody` reads as nil because
                // the system converts it to `httpBodyStream`.
                request: context.requestSnapshot,
                decryptor: decryptor,
                mode: context.mode
            )
        }

        let dataTask = Self.sharedSession.dataTask(with: sanitizedRequest)
        self.dataTask = dataTask
        Self.sessionDelegate.register(self, for: dataTask)
        dataTask.resume()
    }

    public override func stopLoading() {
        if let dataTask {
            Self.sessionDelegate.unregister(dataTask)
            dataTask.cancel()
        }
        dataTask = nil
    }

    /// Copy handed to the internal session: the lifecycle context is removed
    /// and the request is marked handled so it can't be re-intercepted.
    private func sanitizedInterceptedRequest(from request: URLRequest) -> URLRequest {
        let fallbackURL = request.url ?? URL(string: "about:blank")!
        let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest ?? NSMutableURLRequest(url: fallbackURL)

        NetworkInspectorRequestContext.removeContext(from: mutableRequest)
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutableRequest)
        return mutableRequest as URLRequest
    }

    private func beginLifecycle(
        _ lifecycle: InspectedChain,
        kind: AttemptKind,
        request: NetworkRequestSnapshot,
        decryptor: AttemptDecryptor?,
        mode: RequestMode
    ) {
        lifecycle.beginAttempt(
            kind: kind,
            request: request,
            decryptor: decryptor,
            mode: mode
        )
    }

    private func completeLifecycle(error: Error?) {
        guard let lifecycle else { return }

        if let error {
            lifecycle.completeCurrentAttempt(
                result: .failure(
                    error: error,
                    partialData: receivedData.isEmpty ? nil : receivedData,
                    response: response.map { NetworkResponseSnapshot(response: $0) }
                )
            )
            return
        }

        guard let response else {
            lifecycle.completeCurrentAttempt(
                result: .failure(
                    error: MissingProtocolResponseError(),
                    partialData: receivedData.isEmpty ? nil : receivedData,
                    response: nil
                )
            )
            return
        }

        lifecycle.completeCurrentAttempt(
            result: .success(
                data: receivedData,
                response: NetworkResponseSnapshot(response: response)
            )
        )
    }

    // MARK: - Callbacks routed from the shared session delegate
    //
    // Instance state below is only touched from the shared session's serial
    // delegate queue, so no extra synchronization is needed.

    fileprivate func didReceive(
        response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        self.response = response
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }

    fileprivate func didReceive(data: Data) {
        receivedData.append(data)
        client?.urlProtocol(self, didLoad: data)
    }

    fileprivate func didReceive(
        challenge: URLAuthenticationChallenge,
        session: URLSession,
        task: URLSessionTask,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if let taskDelegate = forwardedDelegate as? URLSessionTaskDelegate,
           taskDelegate.responds(to: #selector(URLSessionTaskDelegate.urlSession(_:task:didReceive:completionHandler:))) {
            taskDelegate.urlSession?(session, task: task, didReceive: challenge, completionHandler: completionHandler)
            return
        }

        if let sessionDelegate = forwardedDelegate {
            sessionDelegate.urlSession?(
                session,
                didReceive: challenge,
                completionHandler: completionHandler
            )
            return
        }

        completionHandler(.performDefaultHandling, nil)
    }

    fileprivate func didComplete(error: Error?) {
        if let error {
            completeLifecycle(error: error)
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            completeLifecycle(error: nil)
            client?.urlProtocolDidFinishLoading(self)
        }

        dataTask = nil
    }
}

// MARK: - MultiplexingSessionDelegate

/// Routes shared-session callbacks to the protocol instance that owns each
/// task. Instances are registered in `startLoading` and removed on completion
/// or `stopLoading` — whichever comes first — so they are retained exactly as
/// long as their load.
private final class MultiplexingSessionDelegate: NSObject, URLSessionDataDelegate {

    private let lock = NSLock()
    private var handlers: [Int: NetworkInspectorURLProtocol] = [:]

    func register(_ handler: NetworkInspectorURLProtocol, for task: URLSessionTask) {
        lock.lock()
        defer { lock.unlock() }
        handlers[task.taskIdentifier] = handler
    }

    func unregister(_ task: URLSessionTask) {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeValue(forKey: task.taskIdentifier)
    }

    private func handler(for task: URLSessionTask) -> NetworkInspectorURLProtocol? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[task.taskIdentifier]
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let handler = handler(for: dataTask) else {
            completionHandler(.cancel)
            return
        }
        handler.didReceive(response: response, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        handler(for: dataTask)?.didReceive(data: data)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let handler = handler(for: task) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        handler.didReceive(
            challenge: challenge,
            session: session,
            task: task,
            completionHandler: completionHandler
        )
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let handler = handler(for: task) else { return }
        unregister(task)
        handler.didComplete(error: error)
    }
}

private struct MissingProtocolResponseError: LocalizedError {
    var errorDescription: String? {
        "The URLProtocol interceptor completed without response metadata."
    }
}
