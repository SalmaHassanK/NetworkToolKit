//
//  ChainBusinessInsights.swift
//  NetworkInspector
//
//  Host-supplied extension point that injects app-specific knowledge of the
//  response envelope into the otherwise transport-only logger:
//  parsing `globalStatus`, `requestId`, mapping enum cases to badge colors,
//  and adding extra rows to the overview screen.
//
//  Without an insights provider the logger renders only HTTP-level outcome.
//

import Foundation

// MARK: - StatusBadge / BadgeSeverity

/// A short colored label rendered as a pill in the logger UI.
public struct StatusBadge {
    public let text: String
    public let severity: BadgeSeverity

    public init(text: String, severity: BadgeSeverity) {
        self.text = text
        self.severity = severity
    }
}

/// Transport-agnostic severity used to pick the pill tint.
public enum BadgeSeverity {
    case success
    case warning
    case danger
    case neutral
    case info
}

// MARK: - ChainBusinessContext

/// Read-only view of a chain passed to insights providers. Exposes only the
/// raw response payload pieces a host needs to derive its own status / IDs —
/// keeps the logger's internal model (`APIRequestChain`, `APIAttempt`) hidden.
public protocol ChainBusinessContext: AnyObject {
    var correlationId: String { get }
    var tag: String { get }
    var url: URL { get }

    /// Body of the primary (non-fallback, non-push) attempt, if any.
    var primaryResponseBody: String? { get }
    /// Body of the most recent attempt — could be a fallback or push.
    var lastResponseBody: String? { get }
    /// HTTP status code of the last attempt, if it produced an HTTP response.
    var lastHTTPStatusCode: Int? { get }
}

// MARK: - ChainBusinessInsights

/// Optional hook the host implements to surface envelope-specific data in
/// the logger UI. The protocol is intentionally generic:
///
/// - ``badges(for:)`` returns the pill labels rendered next to each chain
///   row in the list (e.g. business status, global status, custom flags).
/// - ``overviewRows(for:)`` returns the `(label, value)` pairs appended to
///   the chain detail screen's Overview section (backend ids, error codes,
///   anything host-specific).
///
/// The logger itself knows nothing about which fields exist in any given
/// response envelope — each host packs whatever it parses into these two
/// flat collections.
public protocol ChainBusinessInsights {
    /// Pill badges shown on the chain list row. Order is preserved; the cell
    /// falls back to a transport-level HTTP outcome badge when this is empty.
    func badges(for chain: ChainBusinessContext) -> [StatusBadge]

    /// Extra `(label, value)` rows appended to the chain detail Overview section.
    func overviewRows(for chain: ChainBusinessContext) -> [(String, String)]
}

public extension ChainBusinessInsights {
    func badges(for chain: ChainBusinessContext) -> [StatusBadge] { [] }
    func overviewRows(for chain: ChainBusinessContext) -> [(String, String)] { [] }
}

// MARK: - APIRequestChain conformance

extension APIRequestChain: ChainBusinessContext {
    public var correlationId: String { id }

    public var primaryResponseBody: String? { primaryAttempt?.response?.body }
    public var lastResponseBody: String? { lastAttempt?.response?.body }
    public var lastHTTPStatusCode: Int? { lastAttempt?.response?.httpStatusCode }
}

// MARK: - Internal pill mapping

extension BadgeSeverity {
    var pillStyle: PillLabel.Style {
        switch self {
        case .success: return .success
        case .warning: return .warning
        case .danger:  return .danger
        case .neutral: return .neutral
        case .info:    return .push
        }
    }
}

extension AttemptOutcome {
    /// Default badge used when no insights provider is wired — falls back to
    /// the HTTP-level outcome so the cell still renders something meaningful.
    var defaultStatusBadge: StatusBadge {
        let severity: BadgeSeverity
        switch self {
        case .success:      severity = .success
        case .clientError:  severity = .warning
        case .serverError:  severity = .danger
        case .networkError: severity = .danger
        case .unknown:      severity = .neutral
        }
        return StatusBadge(text: displayTitle, severity: severity)
    }
}
