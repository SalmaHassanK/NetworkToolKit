//
//  AttemptRequest.swift
//  MPesaNetworkService
//
//  Created by Salma Kamal Eldin, Vodafone on 20/06/2026.
//

// MARK: - Request / Response Snapshots

/// Immutable snapshot of the request that was sent for a single attempt.
/// Captured when the recorder records a new attempt.
struct AttemptRequest {
    let id: String
    let kind: AttemptKind
    let target: String
    let httpMethod: String
    let headers: [String: String]
    let body: Data?
    let startedAt: Date
}
