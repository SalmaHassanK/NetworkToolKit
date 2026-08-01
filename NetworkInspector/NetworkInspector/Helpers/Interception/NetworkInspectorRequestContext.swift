//
//  NetworkInspectorRequestContext.swift
//  NetworkInspector
//
//  In-process request context carried from the instrumentation call site
//  into `NetworkInspectorURLProtocol` as a `URLProtocol` request property.
//
//  URLProtocol properties live only inside the URL loading system — they are
//  never serialized onto the wire — so no header smuggling, sanitization
//  pass, or out-of-band registry is needed.
//

import Foundation

/// Lifecycle context for one instrumented request. Attached to the outgoing
/// `URLRequest` via `URLProtocol.setProperty` and read back by
/// `NetworkInspectorURLProtocol` when it takes over the load. Restarted loads
/// see the same context; `InspectedChain` ignores a repeated
/// begin for an attempt already in flight.
final class NetworkInspectorRequestContext: NSObject {

    private static let propertyKey = "NetworkInspectorRequestContext"

    let lifecycle: InspectedChain
    let kind: AttemptKind
    let mode: RequestMode
    let decryptor: AttemptDecryptor?
    let forwardedDelegate: URLSessionDelegate?
    let requestSnapshot: NetworkRequestSnapshot

    private init(
        lifecycle: InspectedChain,
        kind: AttemptKind,
        mode: RequestMode,
        decryptor: AttemptDecryptor?,
        forwardedDelegate: URLSessionDelegate?,
        requestSnapshot: NetworkRequestSnapshot
    ) {
        self.lifecycle = lifecycle
        self.kind = kind
        self.mode = mode
        self.decryptor = decryptor
        self.forwardedDelegate = forwardedDelegate
        self.requestSnapshot = requestSnapshot
    }

    /// Returns a copy of `request` carrying the lifecycle context as a
    /// URLProtocol property.
    ///
    /// The request is snapshotted here, while `httpBody` is still readable —
    /// once the request enters the URL loading system the body is converted
    /// to `httpBodyStream` and reads as nil inside the URLProtocol.
    static func attach(
        to request: URLRequest,
        chain: InspectedChain,
        kind: AttemptKind,
        mode: RequestMode,
        decryptor: AttemptDecryptor?,
        forwardedDelegate: URLSessionDelegate?
    ) -> URLRequest {
        let context = NetworkInspectorRequestContext(
            lifecycle: chain,
            kind: kind,
            mode: mode,
            decryptor: decryptor,
            forwardedDelegate: forwardedDelegate,
            requestSnapshot: NetworkRequestSnapshot(request: request)
        )

        let fallbackURL = request.url ?? URL(string: "about:blank")!
        let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest ?? NSMutableURLRequest(url: fallbackURL)
        URLProtocol.setProperty(context, forKey: propertyKey, in: mutableRequest)
        return mutableRequest as URLRequest
    }

    /// Reads the context previously attached with `attach(to:...)`, if any.
    static func context(for request: URLRequest) -> NetworkInspectorRequestContext? {
        URLProtocol.property(forKey: propertyKey, in: request) as? NetworkInspectorRequestContext
    }

    /// Strips the context property from a request so the copy handed to the
    /// protocol's internal session carries no inspector state.
    static func removeContext(from request: NSMutableURLRequest) {
        URLProtocol.removeProperty(forKey: propertyKey, in: request)
    }
}
