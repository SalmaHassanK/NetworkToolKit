//
//  NetworkTransportSnapshots.swift
//  NetworkInspector
//
//  Platform-agnostic transport snapshots used by the core lifecycle and
//  recorder abstractions. iOS URLSession helpers bridge into these types, and
//  Android can build the same model from OkHttp or another transport stack.
//

import Foundation

public struct NetworkRequestSnapshot {
    public let target: String
    public let method: String
    public let headers: [String: String]
    public let body: Data?
    public let startedAt: Date

    public init(
        target: String,
        method: String,
        headers: [String: String] = [:],
        body: Data? = nil,
        startedAt: Date = Date()
    ) {
        self.target = target
        self.method = method
        self.headers = headers
        self.body = body
        self.startedAt = startedAt
    }
}

public struct NetworkResponseSnapshot {
    public let statusCode: Int?
    public let headers: [String: String]
    public let endedAt: Date

    public init(
        statusCode: Int?,
        headers: [String: String] = [:],
        endedAt: Date = Date()
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.endedAt = endedAt
    }
}

public extension NetworkRequestSnapshot {
    init(request: URLRequest, startedAt: Date = Date()) {
        self.init(
            target: request.url?.absoluteString ?? "request",
            method: request.httpMethod ?? "GET",
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody,
            startedAt: startedAt
        )
    }
}

public extension NetworkResponseSnapshot {
    init(response: URLResponse, endedAt: Date = Date()) {
        let http = response as? HTTPURLResponse
        let headers = http?.allHeaderFields.reduce(into: [String: String]()) { partialResult, entry in
            partialResult[String(describing: entry.key)] = String(describing: entry.value)
        } ?? [:]

        self.init(
            statusCode: http?.statusCode,
            headers: headers,
            endedAt: endedAt
        )
    }
}
