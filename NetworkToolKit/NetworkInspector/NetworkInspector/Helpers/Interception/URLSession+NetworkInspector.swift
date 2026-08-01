//
//  URLSession+NetworkInspector.swift
//  NetworkInspector
//
//  URLSession surface of the inspector API. Sessions are built through
//  `NetworkInspector.shared.makeSession(...)`; tracked tasks are issued
//  through the `dataTask(with:inspection:)` overload below. Chain identity
//  is carried entirely by `InspectionContext.correlationId` — attempts with
//  the same ID land on the same chain (get-or-create, atomic in
//  `ChainRegistry`), so there is no chain handle to hold.
//

import Foundation

// MARK: - InspectionContext

/// Everything the inspector needs to record one HTTP attempt, declared at
/// issue time. Reusing the same `correlationId` across attempts groups them
/// into one chain; a fresh ID opens a new chain.
///
/// Attempts issued through this API are always `.http`; push completions are
/// recorded explicitly via `recordPushCompletion`.
public struct InspectionContext {

    /// Stable key shared by every attempt of one logical request.
    public var correlationId: String

    /// Human-readable label (analytics identifier / URL path) shown in the
    /// UI. Only the value supplied when the chain opens is used.
    public var tag: String

    /// Decryptor for this attempt's payloads; also becomes the chain's
    /// default when the chain opens with this attempt.
    public var decryptor: AttemptDecryptor?

    /// How this attempt relates to the logical request: `.sync` closes the
    /// chain on completion, `.async` consults its `isTerminal` closure.
    public var mode: RequestMode

    public init(
        correlationId: String = UUID().uuidString,
        tag: String,
        decryptor: AttemptDecryptor? = nil,
        mode: RequestMode = .sync
    ) {
        self.correlationId = correlationId
        self.tag = tag
        self.decryptor = decryptor
        self.mode = mode
    }
}

// MARK: - Issuing tracked tasks

public extension URLSession {

    /// Creates a data task whose round-trip is recorded as an attempt of the
    /// chain identified by `inspection.correlationId`. The task is returned
    /// suspended; call `resume()`.
    ///
    /// If no live chain exists for the ID a new one opens; if one is waiting
    /// for a follow-up (an `.async` attempt returned `.keepOpen`), this
    /// attempt is appended to it.
    func dataTask(
        with request: URLRequest,
        inspection: InspectionContext,
        completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {
        networkInspectorDataTask(
            with: request,
            inspection: inspection,
            completionHandler: completionHandler
        )
    }
}

// MARK: - Internal adapters

extension URLSession {
    /// Builds a session with the inspector's URLProtocol installed.
    /// Called by `NetworkInspector.makeSession(...)`.
    static func networkInspectorSession(
        configuration: URLSessionConfiguration = .default,
        forwardingTo delegate: URLSessionDelegate? = nil,
        delegateQueue: OperationQueue? = nil
    ) -> URLSession {
        let sessionConfiguration = configuration.copy() as? URLSessionConfiguration ?? configuration
        var protocolClasses = sessionConfiguration.protocolClasses ?? []
        if protocolClasses.contains(where: { $0 == NetworkInspectorURLProtocol.self }) == false {
            protocolClasses.insert(NetworkInspectorURLProtocol.self, at: 0)
        }
        sessionConfiguration.protocolClasses = protocolClasses

        return URLSession(
            configuration: sessionConfiguration,
            delegate: delegate,
            delegateQueue: delegateQueue
        )
    }

    /// Backs the public `dataTask(with:inspection:)` overload above.
    func networkInspectorDataTask(
        with request: URLRequest,
        inspection: InspectionContext,
        completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {
        // Atomic get-or-create: same correlation ID → same chain.
        let chain = ChainRegistry.shared.chain(
            correlationId: inspection.correlationId,
            tag: inspection.tag,
            defaultDecryptor: inspection.decryptor
        )

        let interceptedRequest = NetworkInspectorRequestContext.attach(
            to: request,
            chain: chain,
            kind: .http,
            mode: inspection.mode,
            decryptor: inspection.decryptor,
            forwardedDelegate: delegate
        )

        return dataTask(with: interceptedRequest) { data, response, error in
            completionHandler(data, response, error)
        }
    }
}

private struct MissingURLSessionResponseError: LocalizedError {
    var errorDescription: String? {
        "The URLSession request completed without data or response."
    }
}
