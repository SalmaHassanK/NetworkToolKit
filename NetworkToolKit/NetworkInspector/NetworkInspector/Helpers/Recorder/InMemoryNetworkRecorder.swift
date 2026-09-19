//
//  InMemoryNetworkRecorder.swift
//  NetworkInspector
//
//  In-process recorder + reader used by `NetworkInspector.shared.enable()`.
//  Keeps chains in memory and exposes them through an observable
//  `MutableProperty` for the inspector UI to consume.
//
//  ## Threading
//  All mutations go through a concurrent `DispatchQueue` using barrier writes,
//  so the UI can read `chains.value` without contention while the recorder
//  appends new attempts.
//
//  ## Eviction
//  Driven by the active ``NetworkInspectorConfiguration`` (host-supplied via
//  ``NetworkInspector/enable(uiConfiguration:configuration:)``):
//  - `maxChains` caps total chains; oldest are dropped on overflow.
//  - `maxPendingChains` caps unresolved chains.
//  - `pendingChainTTL` evicts unresolved chains to prevent memory leaks.
//

import Foundation
import ReactiveSwift

final class InMemoryNetworkRecorder: NetworkInspectorRecorder, NetworkInspectorReadable {

    // MARK: - Singleton

    static let shared = InMemoryNetworkRecorder()
    private init() {}

    // MARK: - Storage

    /// Observable list of all recorded chains, newest first. The inspector UI
    /// binds to this directly.
    let chains: MutableProperty<[APIRequestChain]> = MutableProperty([])

    /// Build environment label shown in the UI title. `nil` means the host
    /// did not supply one; the panel and export files omit the segment.
    /// Set by the host app at the moment it calls
    /// `NetworkInspector.shared.enable(uiConfiguration:configuration:)`.
    var environmentName: String?

    private struct PendingEntry {
        let chain: APIRequestChain
        let createdAt: Date
    }
    private var pending: [String: PendingEntry] = [:]

    private let queue = DispatchQueue(
        label: "com.devtools.InMemoryNetworkInspector",
        attributes: .concurrent
    )

    /// Active eviction tunables. All reads/writes go through `queue`.
    private var _configuration: NetworkInspectorConfiguration = .init()

    /// Replaces the active eviction tunables. Called by the facade when the
    /// host supplies a `NetworkInspectorConfiguration` via `enable(...)`.
    func applyConfiguration(_ configuration: NetworkInspectorConfiguration) {
        queue.sync(flags: .barrier) { self._configuration = configuration }
    }

    // MARK: - NetworkInspectorRecorder

    func startRequestChain(
        correlationId: String,
        tag: String,
        kind: AttemptKind,
        request: NetworkRequestSnapshot,
        decryptor: AttemptDecryptor?
    ) {
        queue.sync(flags: .barrier) {
            pruneLocked(now: Date())

            if pending[correlationId] != nil { return } // idempotent

            let chain = APIRequestChain(
                tag: tag,
                requestId: correlationId
            )

            appendAttempt(
                to: chain,
                kind: kind,
                request: request,
                decryptor: decryptor
            )

            pending[correlationId] = PendingEntry(chain: chain, createdAt: Date())
            let maxChains = _configuration.maxChains
            chains.modify {
                $0.insert(chain, at: 0)
                if $0.count > maxChains {
                    $0 = Array($0.prefix(maxChains))
                }
            }
        }
    }

    func appendToRequestChain(
        with correlationId: String,
        kind: AttemptKind,
        request: NetworkRequestSnapshot,
        decryptor: AttemptDecryptor?
    ) {
        queue.sync(flags: .barrier) {
            guard let chain = pending[correlationId]?.chain else { return }
            appendAttempt(
                to: chain,
                kind: kind,
                request: request,
                decryptor: decryptor
            )
            // Re-open the chain so the UI shows it as in-progress again
            // until the next response arrives.
            chain.isResolved.value = false
        }
    }

    func completeCurrentAttempt(
        correlationId: String,
        result: AttemptResult,
        keepChainOpen: Bool
    ) {
        // Snapshot the target under a read, run `unpack` (which may decrypt
        // and UTF-8-decode the whole body) outside the barrier so slow bodies
        // don't serialize recording across the app, then commit. The commit
        // targets the captured attempt object, so attempts appended in
        // between can't receive the wrong response.
        let target: (chain: APIRequestChain, attempt: APIAttempt)? = queue.sync {
            guard let chain = pending[correlationId]?.chain,
                  let attempt = chain.lastAttempt
            else { return nil }
            return (chain, attempt)
        }
        guard let (chain, attempt) = target else { return }

        let (response, outcome) = Self.unpack(
            result: result,
            decryptor: attempt.decryptor
        )

        queue.sync(flags: .barrier) {
            attempt.setResponse(response)
            attempt.outcome = outcome
            if keepChainOpen == false {
                pending.removeValue(forKey: correlationId)
                chain.isResolved.value = true
            } else {
                chain.isResolved.value = false
            }
            chain.attempts.modify { _ in } // trigger UI update
        }
    }

    func closeRequestChain(correlationId: String) {
        queue.sync(flags: .barrier) {
            guard let chain = pending.removeValue(forKey: correlationId)?.chain else { return }
            chain.isResolved.value = true
            chain.attempts.modify { _ in }
        }
    }

    // MARK: - Helpers

    /// Builds an `APIAttempt` from the inputs and appends it to the chain.
    private func appendAttempt(
        to chain: APIRequestChain,
        kind: AttemptKind,
        request: NetworkRequestSnapshot,
        decryptor: AttemptDecryptor?
    ) {
        let attemptRequest = AttemptRequest(
            id: UUID().uuidString,
            kind: kind,
            target: request.target,
            httpMethod: request.method,
            headers: request.headers,
            body: Self.decrypt(request.body, decryptor: decryptor) ?? request.body,
            startedAt: request.startedAt
        )
        let attempt = chain.addAttemptOrReturnIfExist(request: attemptRequest)
        attempt.decryptor = decryptor
    }

    private func pruneLocked(now: Date) {
        let ttl = _configuration.pendingChainTTL
        if ttl > 0 {
            pending = pending.filter { now.timeIntervalSince($0.value.createdAt) < ttl }
        }
        let overflow = pending.count - _configuration.maxPendingChains
        guard overflow > 0 else { return }
        let oldest = pending.sorted { $0.value.createdAt < $1.value.createdAt }
        for (id, _) in oldest.prefix(overflow) {
            pending.removeValue(forKey: id)
        }
    }

    func clearAll() {
        queue.sync(flags: .barrier) {
            self.chains.value = []
            self.pending.removeAll()
        }
    }

    // MARK: - Result Unpacking

    /// Maps the transport-level `AttemptResult` into the pair the UI
    /// machinery expects: an `AttemptResponse` snapshot (with body decrypted
    /// eagerly when a `decryptor` is present) and the derived
    /// `AttemptOutcome` badge.
    ///
    /// Decryption runs inline so the UI shows plaintext without any user
    /// gesture. If decryption throws, the body falls back to a base64
    /// rendering of the ciphertext.
    private static func unpack(
        result: AttemptResult,
        decryptor: AttemptDecryptor?
    ) -> (response: AttemptResponse, outcome: AttemptOutcome) {
        switch result {
        case .success(let data, let response):
            let body = renderBody(data, decryptor: decryptor)
            let snapshot = AttemptResponse(
                httpStatusCode: response.statusCode,
                headers: response.headers,
                body: body,
                endedAt: response.endedAt
            )
            let outcome: AttemptOutcome = {
                guard let status = response.statusCode else { return .unknown }
                switch status {
                case 200..<300: return .success(statusCode: status)
                case 400..<500: return .clientError(errorMessage: body ?? "HTTP \(status)")
                default:        return .serverError(
                    httpStatusCode: status,
                    errorMessage: body ?? "HTTP \(status)"
                )
                }
            }()
            return (snapshot, outcome)

        case .failure(let error, let partial, let response):
            let body = partial.flatMap { renderBody($0, decryptor: decryptor) }
            let snapshot = AttemptResponse(
                httpStatusCode: response?.statusCode,
                headers: response?.headers ?? [:],
                body: body,
                endedAt: response?.endedAt ?? Date()
            )
            return (snapshot, .networkError(errorMessage: error.localizedDescription))
        }
    }

    /// If a decryptor is present, try it; on success show plaintext, on
    /// throw fall back to ciphertext base64. Without a decryptor, treat the
    /// bytes as UTF-8 (plaintext) or fall back to base64 for binary payloads.
    private static func renderBody(_ data: Data, decryptor: AttemptDecryptor?) -> String? {
        if let decryptor, let plain = try? decryptor(data) {
            return String(data: plain, encoding: .utf8) ?? plain.base64EncodedString()
        } else {
            return String(data: data, encoding: .utf8) ?? data.base64EncodedString()
        }
    }

    private static func decrypt(_ data: Data?, decryptor: AttemptDecryptor?) -> Data? {
        guard let data else { return nil }
        return try? decryptor?(data)
    }
}
