//
//  APIRequestChain.swift
//  MPesaNetworkService
//
//  Created by Salma Kamal Eldin, Vodafone on 20/06/2026.
//

import Foundation
import ReactiveSwift

// ## Model hierarchy
// ```
// APIRequestChain (ChainDisplayable) – one logical operation (e.g. "send payment")
//   └─ [APIAttempt] (AttemptDisplayable) – individual network attempts within the chain
//        ├─ AttemptRequest  – captured request metadata (URL, method, headers, body)
//        └─ AttemptResponse – captured response metadata (status, headers, body)
// ```

// MARK: - APIRequestChain

/// A logical network operation that may span multiple attempts (primary, fallback, push).
///
/// Internal mutation (`addAttemptOrReturnIfExist`) is used by the recorder.
/// UI consumers should access data through the ``ChainDisplayable`` protocol.
final class APIRequestChain {
    let id: String
    let tag: String
    let createdAt: Date

    let attempts: MutableProperty<[APIAttempt]> = MutableProperty([])
    let isResolved: MutableProperty<Bool> = MutableProperty(false)

    var httpAttempts: [APIAttempt] { attempts.value.filter { !$0.isExternalCompletion } }
    var primaryAttempt: APIAttempt? { httpAttempts.first }
    var lastAttempt: APIAttempt? { attempts.value.last }

    init(tag: String, requestId: String) {
        self.id  = requestId
        self.tag = tag
        self.createdAt = Date()
    }

    /// Appends a new attempt to the chain, or returns the existing one if an attempt
    /// with the same `request.id` already exists (idempotent).
    @discardableResult
    func addAttemptOrReturnIfExist(request: AttemptRequest) -> APIAttempt {
        if let existing = attempts.value.first(where: { $0.request.id == request.id }) { return existing }
        let attempt = APIAttempt(request: request, index: httpAttempts.count)
        attempts.modify { $0.append(attempt) }
        return attempt
    }
}
