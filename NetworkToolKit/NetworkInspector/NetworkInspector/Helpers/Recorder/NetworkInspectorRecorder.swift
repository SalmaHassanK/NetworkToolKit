//
//  NetworkInspectorRecorder.swift
//  NetworkInspector
//
//  Recording contract for the network inspector.
//
//  ## Shape
//  - `startRequestChain` opens a new chain keyed by `correlationId`.
//  - `appendToRequestChain` appends a follow-up attempt (fallback, silent push,
//    retry…) onto an existing chain.
//  - `completeCurrentAttempt` records the outcome of the last attempt and
//    either closes the chain or keeps it open for follow-ups.
//  - `closeRequestChain` closes a chain whose last attempt was already completed.
//
//  ## Correlation ID
//  The chain key. Two attempts share a chain iff the caller passes the same
//  `correlationId`. The ID is supplied in-process by the network layer at the
//  recorder call site — it is never written to or read from an HTTP header,
//  so backend contracts are unaffected.
//
//  ## Decryptor
//  Per-request closure captured at encryption time
//  (see `SecureChannel.EncryptedRequestComponents.decryptor`). Stored on the
//  attempt and invoked lazily by the inspector UI on tap. Closure owns its
//  cipher, so session-key rotation does not invalidate it.
//
//  ## Enabling
//  `NetworkInspector.shared.enable(environment:)` turns recording on by
//  installing the in-memory recorder. While disabled, the interceptor
//  short-circuits on the nil-check (`NetworkInspector.shared.recorder?…`)
//  so production builds pay zero cost.
//

import Foundation
import Combine

/// Lazy ciphertext-to-plaintext closure captured at encryption time.
/// Stored per attempt and invoked by the inspector UI only when the user
/// opens it.
public typealias AttemptDecryptor = (Data) throws -> Data

/// Read-only surface the inspector UI (``APILogsPanelVC``, ``APILogExporter``)
/// uses to access recorded chains. The concrete recorder
/// ``InMemoryNetworkInspector`` conforms to this so the UI stays decoupled
/// from the recording implementation.
protocol NetworkInspectorReadable: AnyObject {
    var chains: CurrentValueSubject<[APIRequestChain], Never> { get }
    var environmentName: String? { get }
    func clearAll()
}

/// Classifies an attempt within a chain. Drives UI labelling and result mapping.
public enum AttemptKind: Equatable {
    /// HTTP round-trip attempt.
    case http
    /// Out-of-band completion delivered via push notification, resolving an
    /// existing logical request after the HTTP round-trip has finished.
    case pushNotification
}

public extension AttemptKind {
    /// `true` for synthetic completions delivered outside an HTTP round-trip.
    /// Drives type-specific UI rendering.
    var isExternalCompletion: Bool {
        self == .pushNotification
    }
}

/// Terminal outcome for an attempt. Carries raw transport bytes so the UI can
/// render ciphertext or invoke the attempt's decryptor on demand.
public enum AttemptResult {
    case success(data: Data, response: NetworkResponseSnapshot)
    case failure(error: Error, partialData: Data?, response: NetworkResponseSnapshot?)
}

/// The 3-method recording contract called by the network layer.
///
/// Implementations are responsible for:
/// - thread-safe storage of chains keyed by `correlationId`,
/// - eviction policy (max chains, TTL on unresolved chains),
/// - exposing chains to the inspector UI.
protocol NetworkInspectorRecorder: AnyObject {

    /// Open a new chain. Idempotent — calling with the same `correlationId`
    /// of an unresolved chain is a no-op.
    ///
    /// - Parameters:
    ///   - correlationId: Stable key shared by every attempt in this chain.
    ///   - tag: Human-readable label (analytics identifier / URL path).
    ///   - kind: Classification of the chain's first attempt. Chains open
    ///     with `.http`; `.pushNotification` opens a chain only when the
    ///     completion arrives for an unknown correlation ID.
    ///   - request: Portable transport snapshot captured by the host adapter.
    ///   - decryptor: Per-request decryptor for the response, captured at
    ///     encryption time. `nil` for plaintext flows (OAuth, negotiation,
    ///     unsecured).
    func startRequestChain(
        correlationId: String,
        tag: String,
        kind: AttemptKind,
        request: NetworkRequestSnapshot,
        decryptor: AttemptDecryptor?
    )

    /// Append a follow-up attempt to an existing chain.
    ///
    /// Used for fallback HTTP retries and silent-push deliveries that
    /// resolve a pending sync request.
    func appendToRequestChain(
        with correlationId: String,
        kind: AttemptKind,
        request: NetworkRequestSnapshot,
        decryptor: AttemptDecryptor?
    )

    /// Record the terminal outcome of the current attempt without necessarily
    /// closing the logical request chain. Use this when the HTTP round-trip has
    /// finished, but the overall request may continue through fallback, polling,
    /// push delivery, or another synthetic follow-up.
    func completeCurrentAttempt(
        correlationId: String,
        result: AttemptResult,
        keepChainOpen: Bool
    )

    /// Close the logical request chain after its latest attempt has already
    /// been completed. Useful for multi-stage flows where the transport result
    /// was recorded earlier and a later business decision determines that the
    /// chain is now terminal.
    func closeRequestChain(
        correlationId: String
    )
}

// MARK: - Storage configuration

/// Tunables for the in-memory recorder (storage / eviction only — UI-level
/// options live on ``NetworkInspectorUIConfiguration``).
///
/// - `maxChains`: Maximum number of completed chains to retain.
/// - `maxPendingChains`: Maximum number of unresolved chains to track.
/// - `pendingChainTTL`: Time-to-live for unresolved chains before eviction.
public struct NetworkInspectorConfiguration {
    public var maxChains: Int
    public var maxPendingChains: Int
    public var pendingChainTTL: TimeInterval

    public init(
        maxChains: Int = 200,
        maxPendingChains: Int = 500,
        pendingChainTTL: TimeInterval = 15 * 60 // 15 minutes
    ) {
        self.maxChains = maxChains
        self.maxPendingChains = maxPendingChains
        self.pendingChainTTL = pendingChainTTL
    }
}

// MARK: - UI configuration

/// Output format offered by the inspector's share action.
public enum ExportFormat: CaseIterable {
    /// Human-readable plain-text dump (one `.txt` file).
    case plainText
    /// Markdown dump with collapsible chains/attempts (one `.md` file).
    case markdown
    /// Bruno collection directory zipped for import into the Bruno API client.
    case brunoCollection

    /// Title shown in the format picker action sheet.
    public var displayTitle: String {
        switch self {
        case .plainText:        return "Plain text (.txt)"
        case .markdown:         return "Markdown (.md)"
        case .brunoCollection:  return "Bruno collection (.bru)"
        }
    }
}

/// Host-supplied UI configuration for the inspector. Passed once at
/// ``NetworkInspector/enable(uiConfiguration:)`` time and read back by the
/// inspector view controllers.
///
/// All three fields are UI concerns:
/// - ``environment`` — label rendered in the panel title and export file
///   names. `nil` (default) hides the segment entirely.
/// - ``insights`` — envelope-aware extension point for badges and the
///   "Business insights" section in chain detail.
/// - ``exportFormats`` — formats offered by the share action. With a single
///   format the share dialog opens directly; with more than one a picker is
///   shown first.
public struct NetworkInspectorUIConfiguration {
    public var environment: String?
    public var insights: ChainBusinessInsights?
    public var exportFormats: [ExportFormat]

    public init(
        environment: String? = nil,
        insights: ChainBusinessInsights? = nil,
        exportFormats: [ExportFormat] = [.plainText]
    ) {
        self.environment = environment
        self.insights = insights
        self.exportFormats = exportFormats
    }
}
