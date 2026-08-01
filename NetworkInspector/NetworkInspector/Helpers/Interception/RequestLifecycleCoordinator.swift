//
//  RequestLifecycleCoordinator.swift
//  NetworkInspector
//
//  Chain lifecycle core. `InspectedChain` is the internal state machine for
//  one logical request chain (sync attempt, fallbacks, push/timeout
//  completions); `ChainRegistry` keys live chains by correlation ID with
//  atomic get-or-create, so consumers never hold a handle — they just supply
//  the same correlation ID on every attempt (`InspectionContext`) and the
//  library opens or appends accordingly.
//
//  Whether a completed attempt closes the chain is decided by the request's
//  `RequestMode` — the library closes chains itself; consumers only declare
//  intent.
//

import Foundation

// MARK: - Request mode

/// Snapshot of a finished HTTP attempt handed to an `.async` request's
/// `isTerminal` closure so the consumer can decide whether the logical
/// request is over.
///
/// `body` contains the raw transport bytes; `decryptor` is the attempt's
/// decryptor (if any) so envelope-encrypted payloads can be opened with the
/// consumer's own envelope logic.
public struct CompletedAttempt {
    public let kind: AttemptKind
    public let statusCode: Int?
    public let headers: [String: String]
    public let body: Data
    public let decryptor: AttemptDecryptor?
}

/// Declares, at issue time, how an attempt relates to the logical request —
/// replacing manual keep-open/close bookkeeping.
public enum RequestMode {
    /// One HTTP round-trip is the whole logical request. The chain closes
    /// automatically when the attempt completes (success or failure).
    case sync

    /// The logical request may outlive this attempt. After the attempt
    /// completes successfully, the library asks `isTerminal` whether this
    /// response ended the logical request: `true` closes the chain, `false`
    /// keeps it open for follow-ups. Transport errors never consult the
    /// closure — the chain stays open so a follow-up (fallback, push,
    /// timeout) can still resolve it.
    ///
    /// `maxOpenInterval` bounds how long the chain may sit open waiting for
    /// a follow-up; when it elapses with no new attempt, the library closes
    /// the chain itself. Pass `nil` if the consumer guarantees termination
    /// through its own timeout path.
    case async(maxOpenInterval: TimeInterval?, isTerminal: (CompletedAttempt) -> Bool)

    /// `.async` without a watchdog interval.
    public static func async(isTerminal: @escaping (CompletedAttempt) -> Bool) -> RequestMode {
        .async(maxOpenInterval: nil, isTerminal: isTerminal)
    }
}

// MARK: - ChainRegistry

/// Keys live chains by correlation ID. Get-or-create is atomic: two attempts
/// racing on the same ID always land on the same chain, and an ID whose
/// chain already resolved starts a fresh one. Resolved chains remove
/// themselves via `InspectedChain.didResolve`.
final class ChainRegistry {

    static let shared = ChainRegistry()

    private let lock = NSLock()
    private var chains: [String: InspectedChain] = [:]

    /// Returns the live chain for `correlationId`, creating one if none
    /// exists or the previous one already resolved.
    func chain(
        correlationId: String,
        tag: String,
        defaultDecryptor: AttemptDecryptor?
    ) -> InspectedChain {
        lock.lock()
        defer { lock.unlock() }

        if let existing = chains[correlationId], existing.isResolved == false {
            return existing
        }

        let chain = InspectedChain(
            correlationId: correlationId,
            tag: tag,
            defaultDecryptor: defaultDecryptor
        )
        chain.didResolve = { [weak self] id in
            self?.remove(id)
        }
        chains[correlationId] = chain
        return chain
    }

    /// Returns the live chain for `correlationId`, if any.
    func existingChain(correlationId: String) -> InspectedChain? {
        lock.lock()
        defer { lock.unlock() }
        guard let chain = chains[correlationId], chain.isResolved == false else { return nil }
        return chain
    }

    private func remove(_ correlationId: String) {
        lock.lock()
        defer { lock.unlock() }
        chains.removeValue(forKey: correlationId)
    }
}

// MARK: - InspectedChain

final class InspectedChain {

    private enum State {
        case idle
        case requestInFlight(kind: AttemptKind, mode: RequestMode, decryptor: AttemptDecryptor?)
        case awaitingFollowUp
        case resolved
    }

    let correlationId: String
    let tag: String

    /// Invoked once, right after the chain transitions to `resolved`. Used by
    /// `ChainRegistry` to drop the chain so the correlation ID can be reused.
    var didResolve: ((String) -> Void)?

    private let defaultDecryptor: AttemptDecryptor?
    private let recorderProvider: () -> NetworkInspectorRecorder?

    private let lock = NSLock()
    private var _state: State = .idle
    private var _watchdog: DispatchSourceTimer?

    init(
        correlationId: String,
        tag: String,
        defaultDecryptor: AttemptDecryptor? = nil,
        recorderProvider: @escaping () -> NetworkInspectorRecorder? = { NetworkInspector.shared.recorder }
    ) {
        self.correlationId = correlationId
        self.tag = tag
        self.defaultDecryptor = defaultDecryptor
        self.recorderProvider = recorderProvider
    }

    var isResolved: Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .resolved = _state { return true }
        return false
    }

    static func defaultTag(for request: URLRequest) -> String {
        if let path = request.url?.path, path.isEmpty == false { return path }
        if let host = request.url?.host, host.isEmpty == false { return host }
        return "request"
    }

    // MARK: - Non-HTTP completions

    /// Records a push-notification completion as a synthetic attempt and
    /// resolves the chain.
    func recordPushCompletion(
        request: URLRequest,
        result: AttemptResult,
        decryptor: AttemptDecryptor? = nil
    ) {
        resolveSyntheticAttempt(
            kind: .pushNotification,
            request: NetworkRequestSnapshot(request: request),
            result: result,
            decryptor: decryptor
        )
    }

    /// Records a timeout as a synthetic terminal attempt and resolves the chain.
    func timeout(
        request: URLRequest,
        error: Error
    ) {
        resolveSyntheticAttempt(
            kind: .http,
            request: NetworkRequestSnapshot(request: request),
            result: .failure(error: error, partialData: nil, response: nil)
        )
    }

    // MARK: - Closing

    /// Closes the chain only if it is still open. Safe to call from generic
    /// error paths that don't know whether the chain already resolved.
    func closeIfOpen() {
        lock.lock()
        let currentState = _state
        let canClose: Bool
        switch currentState {
        case .awaitingFollowUp, .requestInFlight:
            canClose = true
        case .idle, .resolved:
            canClose = false
        }

        guard canClose else {
            lock.unlock()
            return
        }
        _state = .resolved
        cancelWatchdogLocked()
        lock.unlock()
        recorderProvider()?.closeRequestChain(correlationId: correlationId)
        didResolve?(correlationId)
    }

    // MARK: - Transport-driven transitions
    //
    // Called by the URLProtocol interceptor and the URLSession adapter. The
    // transport begins/completes attempts; the request's `RequestMode`
    // decides when the chain closes.

    func beginAttempt(
        kind: AttemptKind,
        request: NetworkRequestSnapshot,
        decryptor: AttemptDecryptor? = nil,
        mode: RequestMode = .sync
    ) {
        begin(
            kind: kind,
            request: request,
            decryptor: decryptor,
            mode: mode
        )
    }

//    func beginAttempt(
//        kind: AttemptKind,
//        request: URLRequest,
//        decryptor: AttemptDecryptor? = nil,
//        mode: RequestMode = .sync
//    ) {
//        beginAttempt(
//            kind: kind,
//            request: NetworkRequestSnapshot(request: request),
//            decryptor: decryptor,
//            mode: mode
//        )
//    }

    func completeCurrentAttempt(
        result: AttemptResult,
        expectedKind: AttemptKind? = nil
    ) {
        lock.lock()
        guard case .requestInFlight(let kind, let mode, let decryptor) = _state else {
            lock.unlock()
//            assertionFailure("Attempt completion is only valid while a request is in flight.")
            return
        }
        // `begin` lets an external completion supersede an in-flight HTTP
        // attempt; the superseded round-trip's completion then arrives stale
        // and must not close the follow-up's slot. Callers that know their
        // attempt pass `expectedKind`; transport callers pass nil, which
        // never matches a synthetic attempt.
        let isStale = expectedKind.map { $0 != kind } ?? kind.isExternalCompletion
        guard isStale == false else {
            lock.unlock()
            return
        }
        lock.unlock()

        // Evaluated outside the lock: `.async` modes run the consumer's
        // `isTerminal` closure here, which may decrypt and JSON-parse the
        // whole body — too slow to hold the lock through.
        let keepChainOpen = Self.shouldKeepChainOpen(
            after: result,
            kind: kind,
            mode: mode,
            decryptor: decryptor
        )

        lock.lock()
        // Re-check after the unlocked evaluation: a timeout, a close, or a
        // superseding external completion racing with this completion may
        // have resolved the chain or replaced the in-flight attempt; their
        // transition wins and this completion is dropped.
        guard case .requestInFlight(let currentKind, _, _) = _state, currentKind == kind else {
            lock.unlock()
            return
        }
        _state = keepChainOpen ? .awaitingFollowUp : .resolved
        if keepChainOpen {
            scheduleWatchdogLocked(for: mode)
        } else {
            cancelWatchdogLocked()
        }
        lock.unlock()
        recorderProvider()?.completeCurrentAttempt(
            correlationId: correlationId,
            result: result,
            keepChainOpen: keepChainOpen
        )
        if keepChainOpen == false {
            didResolve?(correlationId)
        }
    }

    func resolveSyntheticAttempt(
        kind: AttemptKind,
        request: NetworkRequestSnapshot,
        result: AttemptResult,
        decryptor: AttemptDecryptor? = nil
    ) {
        beginAttempt(
            kind: kind,
            request: request,
            decryptor: decryptor,
            mode: .sync
        )
        completeCurrentAttempt(result: result, expectedKind: kind)
    }

    // MARK: - Mode evaluation

    private static func shouldKeepChainOpen(
        after result: AttemptResult,
        kind: AttemptKind,
        mode: RequestMode,
        decryptor: AttemptDecryptor?
    ) -> Bool {
        switch mode {
        case .sync:
            return false

        case .async(_, let isTerminal):
            switch result {
            case .failure:
                // Transport errors never consult the closure: a failed
                // attempt isn't terminal — the next poll or push may still
                // resolve the request. The watchdog bounds the wait.
                return true

            case .success(let data, let response):
                let attempt = CompletedAttempt(
                    kind: kind,
                    statusCode: response.statusCode,
                    headers: response.headers,
                    body: data,
                    decryptor: decryptor
                )
                return isTerminal(attempt) == false
            }
        }
    }

    private func begin(
        kind: AttemptKind,
        request: NetworkRequestSnapshot,
        decryptor: AttemptDecryptor?,
        mode: RequestMode
    ) {
        // External completions (push, polling) carry payloads already
        // decrypted by the transport layer and recorded verbatim; inheriting
        // the chain's decryptor would run it over plaintext and garble the
        // body whenever the bogus decryption happens to succeed.
        let effectiveDecryptor = kind.isExternalCompletion
            ? decryptor
            : decryptor ?? defaultDecryptor
        lock.lock()
        let currentState = _state
        switch currentState {
        case .idle:
            // Any kind may open a chain: business chains open with `.http`,
            // while a push completion for an unknown correlation ID opens a
            // fresh chain with `.pushNotification`.
            _state = .requestInFlight(kind: kind, mode: mode, decryptor: effectiveDecryptor)
            lock.unlock()
            recorderProvider()?.startRequestChain(
                correlationId: correlationId,
                tag: tag,
                kind: kind,
                request: request,
                decryptor: effectiveDecryptor
            )

        case .awaitingFollowUp:
            _state = .requestInFlight(kind: kind, mode: mode, decryptor: effectiveDecryptor)
            cancelWatchdogLocked()
            lock.unlock()
            recorderProvider()?.appendToRequestChain(
                with: correlationId,
                kind: kind,
                request: request,
                decryptor: effectiveDecryptor
            )

        case .requestInFlight:
            // An external completion (push / polling) can race the in-flight
            // HTTP attempt — the transport answer is then cancelled, or
            // arrives later and is dropped by the resolved guard. The
            // external completion is the terminal answer for the logical
            // request, so it supersedes the in-flight attempt rather than
            // being dropped; without this the chain dangles open forever.
            guard kind.isExternalCompletion else {
                lock.unlock()
//            assertionFailure("Cannot start a new lifecycle attempt while another attempt is still in flight.")
                break
            }
            _state = .requestInFlight(kind: kind, mode: mode, decryptor: effectiveDecryptor)
            cancelWatchdogLocked()
            lock.unlock()
            recorderProvider()?.appendToRequestChain(
                with: correlationId,
                kind: kind,
                request: request,
                decryptor: effectiveDecryptor
            )

        case .resolved:
            lock.unlock()
//            assertionFailure("Cannot append attempts after the lifecycle has been resolved.")
        }
    }

    // MARK: - Watchdog
    //
    // Bounds how long a chain may sit in `awaitingFollowUp`. Fires only when
    // an `.async` mode specified `maxOpenInterval` and no follow-up attempt
    // arrived in time; closes the chain so it never dangles until eviction.

    private func scheduleWatchdogLocked(for mode: RequestMode) {
        cancelWatchdogLocked()

        guard case .async(let maxOpenInterval?, _) = mode else { return }

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + maxOpenInterval)
        timer.setEventHandler { [weak self] in
            self?.watchdogFired()
        }
        timer.resume()
        _watchdog = timer
    }

    private func cancelWatchdogLocked() {
        _watchdog?.cancel()
        _watchdog = nil
    }

    private func watchdogFired() {
        lock.lock()
        guard case .awaitingFollowUp = _state else {
            lock.unlock()
            return
        }
        _state = .resolved
        cancelWatchdogLocked()
        lock.unlock()
        recorderProvider()?.closeRequestChain(correlationId: correlationId)
        didResolve?(correlationId)
    }
}
