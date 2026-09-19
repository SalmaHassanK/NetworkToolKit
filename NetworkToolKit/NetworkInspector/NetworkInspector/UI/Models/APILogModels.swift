// APILogModels.swift
//
// Data models for the network events logger.
//

//
// UI consumers depend on `AttemptDisplayable` / `ChainDisplayable` protocols only,
// keeping the internal mutation surface (`request`, `response`, `setResponse()`) hidden.

import Foundation
import Combine


// MARK: - Attempt Outcome

/// The resolved outcome of a single network attempt.
///
/// Used by both the cell badges (``ChainCell``, ``AttemptCell``) and the
/// stat bar in ``AttemptDetailVC`` to pick colours and display strings.
enum AttemptOutcome {
    case success(statusCode: Int)
    case clientError(errorMessage: String)
    case serverError(httpStatusCode: Int, errorMessage: String)
    case networkError(errorMessage: String)
    case unknown

    var displayTitle: String {
        switch self {
        case .success:      return "SUCCESS"
        case .clientError:  return "CLIENT ERROR"
        case .serverError:  return "SERVER ERROR"
        case .networkError: return "NETWORK ERROR"
        case .unknown:      return "UNKNOWN"
        }
    }

    var badge: String {
        switch self {
        case .success:      return "✅"
        case .clientError:  return "⚠️"
        case .serverError:  return "🔴"
        case .networkError: return "📡"
        case .unknown:      return "-"
        }
    }
}

// MARK: - Display Protocols

/// Read-only surface consumed by UI cells, detail VCs, and the log exporter.
/// Hides internal mutation (`request`, `response`, `setResponse()`).
protocol AttemptDisplayable: AnyObject {
    var isExternalCompletion: Bool { get }
    var index: Int { get }
    var label: String { get }
    var startedAt: Date { get }
    var durationString: String { get }
    var outcome: AttemptOutcome { get }

    // Request info — always available once the attempt exists.
    var requestURL: String { get }
    var requestHTTPMethod: String { get }
    var requestHeaders: [String: String] { get }
    var requestBody: Data? { get }

    // Response info — nil until the response arrives.
    var httpStatusCode: Int? { get }
    var responseHeaders: [String: String]? { get }
    var responseBody: String? { get }
}

/// Read-only surface consumed by UI cells, detail VCs, and the log exporter.
/// Hides internal mutation (`addAttemptOrReturnIfExist`).
protocol ChainDisplayable: AnyObject {
    var tag: String { get }
    var url: URL { get }
    var totalDurationString: String { get }
    var httpCount: Int { get }
    var fallbackCount: Int { get }
    var externalCompletionCount: Int { get }
    var finalOutcome: AttemptOutcome { get }
    var isResolved: CurrentValueSubject<Bool, Never> { get }
    var attempts: CurrentValueSubject<[APIAttempt], Never> { get }
}


// MARK: - APIAttempt + AttemptDisplayable

extension APIAttempt: AttemptDisplayable {

    var isExternalCompletion: Bool { request.kind.isExternalCompletion }
    var startedAt: Date { request.startedAt }

    var label: String {
        switch request.kind {
        case .http:
            // First HTTP attempt in the chain is the primary; later ones are
            // fallbacks, numbered from 1 by their position.
            return index == 0 ? "Primary" : "Fallback \(index)"
        case .pushNotification:
            return "Push Notification"
        }
    }

    var durationString: String {
        guard let end = response?.endedAt else { return "—" }
        let d = end.timeIntervalSince(startedAt)
        return d < 1 ? String(format: "%.0fms", d * 1000) : String(format: "%.2fs", d)
    }

    // MARK: Flattened request accessors

    var requestURL: String { request.target }
    var requestHTTPMethod: String { request.httpMethod }
    var requestHeaders: [String: String] { request.headers }
    var requestBody: Data? { request.body }

    // MARK: Flattened response accessors

    var httpStatusCode: Int? { response?.httpStatusCode }

    var responseHeaders: [String: String]? {
        response.map(\.headers)
    }

    var responseBody: String? { response?.body }
}



// MARK: - APIRequestChain + ChainDisplayable

extension APIRequestChain: ChainDisplayable {

    var url: URL {
        if let target = primaryAttempt?.request.target ?? lastAttempt?.request.target,
           let url = URL(string: target) {
            return url
        }
        assertionFailure("Chain '\(tag)' (id: \(id)) has no attempts — cannot determine URL")
        return URL(string: "https://unknown")!
    }

    var fallbackCount: Int {
        return max(0, httpAttempts.count - 1)
    }

    var externalCompletionCount: Int { attempts.value.filter { $0.isExternalCompletion }.count }

    var finalOutcome: AttemptOutcome { lastAttempt?.outcome ?? .unknown }

    var totalDuration: TimeInterval? {
        let all = attempts.value
        guard let start = all.first?.startedAt,
              let end = all.last?.response?.endedAt else { return nil }
        return end.timeIntervalSince(start)
    }

    var totalDurationString: String {
        guard let totalDuration = totalDuration else { return "—" }
        return totalDuration < 1 ?
        String(format: "%.0fms", totalDuration * 1000) : String(format: "%.2fs", totalDuration)
    }

    var httpCount: Int {
        httpAttempts.count
    }
}
