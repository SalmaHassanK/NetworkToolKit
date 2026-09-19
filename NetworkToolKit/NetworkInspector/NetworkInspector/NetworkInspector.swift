//
//  NetworkInspector.swift
//  NetworkInspector
//
//  Public facade — the single entry point of the network inspector module.
//
//  ## Usage
//  1. Enable once at app startup (before building your network stack):
//
//     ```swift
//     NetworkInspector.shared.enable(
//         uiConfiguration: .init(
//             environment: "UAT",

//             exportFormats: [.plainText, .markdown]
//         )
//     )
//     ```
//
//  2. Build your session through the facade so the interceptor is installed:
//
//     ```swift
//     let session = NetworkInspector.shared.makeSession(
//         configuration: sessionConfiguration,
//         forwardingTo: certificatePinner
//     )
//     ```
//
//  3. Issue tasks with an `InspectionContext` — the same correlation ID
//     groups attempts into one chain; no handle to hold, nothing to close:
//
//     ```swift
//     let task = session.dataTask(
//         with: request,
//         inspection: .init(
//             correlationId: requestID,
//             tag: "customer_balance",
//             decryptor: decryptor,
//             mode: .async(isTerminal: { … })
//         )
//     ) { … }
//     task.resume()
//     ```
//
//  4. Present the UI from a debug menu:
//
//     ```swift
//     UINavigationController(rootViewController: NetworkInspector.shared.viewController())
//     ```
//

import UIKit

/// Module-level facade that owns the active recorder, the UI configuration,
/// and all consumer-facing entry points (session building, chain creation,
/// inspector UI).
public final class NetworkInspector {

    public static let shared = NetworkInspector()
    private init() {}

    private let lock = NSLock()
    private var _recorder: NetworkInspectorRecorder?
    private var _uiConfiguration: NetworkInspectorUIConfiguration = .init()

    /// Active recorder. `nil` (default) means recording is off — the network
    /// layer short-circuits at the call site so production pays zero cost.
    var recorder: NetworkInspectorRecorder? {
        lock.lock(); defer { lock.unlock() }
        return _recorder
    }

    /// `true` while a recorder is installed. While `false`, the transport
    /// adapters are inert: chains record nothing, tasks degrade to plain
    /// `dataTask`s, and `makeSession` returns an uninstrumented session.
    public var isEnabled: Bool {
        recorder != nil
    }

    /// Snapshot of the UI configuration set via ``enable(uiConfiguration:configuration:)``.
    /// Used by the inspector view controllers when they're constructed.
    public var uiConfiguration: NetworkInspectorUIConfiguration {
        lock.lock(); defer { lock.unlock() }
        return _uiConfiguration
    }

    // MARK: - Lifecycle

    /// Turns recording on, installs the in-memory recorder, and stores the
    /// UI configuration. Idempotent; safe to call multiple times to update
    /// either configuration.
    ///
    /// Call this *before* building sessions with ``makeSession`` — the
    /// interceptor is installed at session-creation time.
    ///
    /// No-op in App Store builds: the inspector is a development tool and
    /// must never record in a store distribution, regardless of what the
    /// host app calls.
    ///
    /// - Parameters:
    ///   - uiConfiguration: Title, badges/overview insights, and share formats.
    ///   - configuration: Eviction tunables (`maxChains`, `maxPendingChains`,
    ///     `pendingChainTTL`). Defaults to the library's built-in values.
    public func enable(
        uiConfiguration: NetworkInspectorUIConfiguration = .init(),
        configuration: NetworkInspectorConfiguration = .init()
    ) {
        let recorder = InMemoryNetworkRecorder.shared
        recorder.environmentName = uiConfiguration.environment
        recorder.applyConfiguration(configuration)
        lock.lock()
        _recorder = recorder
        _uiConfiguration = uiConfiguration
        lock.unlock()
    }

    /// Turns recording off. The in-memory store is preserved so any UI already
    /// presented can still browse what was captured.
    public func disable() {
        lock.lock()
        _recorder = nil
        lock.unlock()
    }

    // MARK: - Sessions

    /// Builds a `URLSession` with the inspector's transport interceptor
    /// installed. While the inspector is disabled this returns a plain,
    /// uninstrumented session — so it is always safe to call.
    ///
    /// - Parameters:
    ///   - configuration: Base configuration; copied before instrumenting.
    ///   - delegate: Session delegate to forward auth challenges to
    ///     (e.g. a certificate pinner). Pinning keeps working under
    ///     interception.
    ///   - delegateQueue: Delegate queue for the session.
    public func makeSession(
        configuration: URLSessionConfiguration = .default,
        forwardingTo delegate: URLSessionDelegate? = nil,
        delegateQueue: OperationQueue? = nil
    ) -> URLSession {
        URLSession.networkInspectorSession(
            configuration: configuration,
            forwardingTo: delegate,
            delegateQueue: delegateQueue
        )
    }

    // MARK: - Chain events (addressed by correlation ID)

    /// Records a push-notification completion as a synthetic attempt on the
    /// chain identified by `correlationId`, and resolves the chain. Opens a
    /// chain if none exists.
    public func recordPushCompletion(
        correlationId: String,
        request: URLRequest,
        result: AttemptResult,
        decryptor: AttemptDecryptor? = nil
    ) {
        guard isEnabled else { return }
        ChainRegistry.shared.chain(
            correlationId: correlationId,
            tag: InspectedChain.defaultTag(for: request),
            defaultDecryptor: decryptor
        )
        .recordPushCompletion(
            request: request,
            result: result,
            decryptor: decryptor
        )
    }

    /// Records a timeout as the terminal attempt of the chain identified by
    /// `correlationId`, and resolves the chain. Opens a chain if none exists.
    public func timeout(
        correlationId: String,
        request: URLRequest,
        error: Error
    ) {
        guard isEnabled else { return }
        ChainRegistry.shared.chain(
            correlationId: correlationId,
            tag: InspectedChain.defaultTag(for: request),
            defaultDecryptor: nil
        )
        .timeout(request: request, error: error)
    }

    /// Escape hatch: closes the chain identified by `correlationId` if it is
    /// still open. For paths outside the transport's knowledge (e.g. a
    /// request pipeline torn down before any terminal event).
    public func closeChainIfOpen(correlationId: String) {
        ChainRegistry.shared.existingChain(correlationId: correlationId)?.closeIfOpen()
    }

    // MARK: - UI

    /// Returns the inspector's root view controller. Wrap in a
    /// `UINavigationController` before presenting.
    public func viewController() -> UIViewController {
        APILogsPanelVC(uiConfiguration: uiConfiguration)
    }
}
