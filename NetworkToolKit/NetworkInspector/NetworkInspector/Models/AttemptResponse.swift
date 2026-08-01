//
//  AttemptResponse.swift
//  NetworkInspector
//
//  Created by Salma Kamal Eldin on 20/06/2026.
//

import Foundation

/// Immutable snapshot of the response received for a single attempt.
struct AttemptResponse {
    /// Raw HTTP status code. `nil` for synthetic completions with no HTTP response.
    let httpStatusCode: Int?
    /// Raw HTTP response headers. Empty when the completion path has no HTTP response.
    let headers: [String: String]
    /// Decrypted response body string (may be JSON or plaintext).
    let body: String?
    /// Timestamp when the response was received / decoded.
    let endedAt: Date
}
