//
//  APIAttempt.swift
//  NetworkInspector
//
//  Created by Salma Kamal Eldin on 20/06/2026.
//


// MARK: - APIAttempt

/// A single network attempt within a request chain.
///
/// Internal state (`request`, `response`) is mutated by the chain tracker.
/// UI consumers should access data through the ``AttemptDisplayable`` protocol.
final class APIAttempt {
    let id: UUID = UUID()
    let index: Int
    let request: AttemptRequest
    private(set) var response: AttemptResponse?
    var outcome: AttemptOutcome = .unknown

    /// Per-request closure captured by the SecureChannel encryption layer.
    /// Invoked lazily by the log UI to turn `encryptedResponseBody` into
    /// plaintext on demand. `nil` for plaintext flows (OAuth, negotiation,
    /// unsecured).
    var decryptor: AttemptDecryptor?

    init(request: AttemptRequest, index: Int) {
        self.request = request
        self.index = index
    }

    func setResponse(_ response: AttemptResponse) {
        self.response = response
    }
}
