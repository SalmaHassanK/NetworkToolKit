//
//  APILogExporter.swift
//  MPesaNetworkService
//
//  Created by Salma Kamal Eldin, Vodafone on 24/03/2026.
//
// Formats tracked request chains into human-readable plain-text logs
// that can be shared via `UIActivityViewController`.
//
// ## Usage
// ```swift
// let text = APILogExporter.exportAll(chains: tracker.chains.value)
// let url  = APILogExporter.writeTempFile(named: APILogExporter.allLogsFileName, content: text)
// // present UIActivityViewController with `url`
// ```
//
// The exported file includes device info, timestamps, and a per-attempt
// breakdown of URL, headers, request/response bodies, and outcome.

import UIKit

/// Stateless utility that converts ``APIRequestChain`` / ``APIAttempt`` data
/// into shareable plain-text log files.
///
/// Implemented as a caseless `enum` to prevent instantiation.
enum APILogExporter {

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private static let fileDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f
    }()

    // MARK: - Device & App Info

    private static var deviceInfo: String {
        let device = UIDevice.current
        let name = device.name            // e.g. "iPhone 15 Pro"
        let systemVersion = device.systemVersion // e.g. "17.2"
        return "\(name) — iOS \(systemVersion)"
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    static var environment: String? {
        environment(tracker: InMemoryNetworkRecorder.shared)
    }

    static func environment(tracker: NetworkInspectorReadable) -> String? {
        tracker.environmentName
    }

    private static var deviceTag: String {
        let device = UIDevice.current
        let model = device.name
        let ios = device.systemVersion
        return "\(fileDateFormatter.string(from: Date()))_\(model)_iOS\(ios)"
    }

    /// File name for all-chains export. Includes the environment segment only
    /// when the host configured one: "20260323_iPhone15Pro_iOS172_AWS-OAT network logs.txt"
    /// vs. "20260323_iPhone15Pro_iOS172 network logs.txt" when env is `nil`.
    static var allLogsFileName: String {
        allLogsFileName(tracker: InMemoryNetworkRecorder.shared, ext: "txt")
    }

    /// File name for all-chains export with a custom extension (e.g. "md", "json").
    static func allLogsFileName(tracker: NetworkInspectorReadable, ext: String) -> String {
        "\(deviceTag)\(envSegment(tracker: tracker)) network logs.\(ext)"
    }

    /// Convenience file name for the Markdown export variant.
    static var allLogsMarkdownFileName: String {
        allLogsFileName(tracker: InMemoryNetworkRecorder.shared, ext: "md")
    }

    /// File name for single chain: "20260323_iPhone15Pro_iOS172_AWS-OAT SomeTag logs.txt"
    static func chainFileName(tag: String, tracker: NetworkInspectorReadable) -> String {
        chainFileName(tag: tag, tracker: tracker, ext: "txt")
    }

    /// File name for single chain with a custom extension (e.g. "md", "json").
    static func chainFileName(tag: String, tracker: NetworkInspectorReadable, ext: String) -> String {
        let safeTag = tag
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return "\(deviceTag)\(envSegment(tracker: tracker)) \(safeTag) logs.\(ext)"
    }

    /// Underscore-prefixed env segment for file names, or empty when env is `nil`.
    private static func envSegment(tracker: NetworkInspectorReadable) -> String {
        environment(tracker: tracker).map { "_\($0)" } ?? ""
    }

    // MARK: - Export All Chains

    /// Produces a full log file with device header, chain count, and every chain's detail.
    static func exportAll(chains: [APIRequestChain], insights: ChainBusinessInsights? = nil) -> String {
        // Reverse so older (earliest) requests appear first in the exported file.
        let chronological = chains.reversed()
        var lines: [String] = []

        lines.append("╔══════════════════════════════════════════════╗")
        lines.append("║           📡  API NETWORK LOGS  📡           ║")
        lines.append("╚══════════════════════════════════════════════╝")
        lines.append("")
        lines.append("📱  Device:      \(deviceInfo)")
        if let environment { lines.append("🌍  Environment: \(environment)") }
        lines.append("🏗️  Version:     \(appVersion) (\(buildNumber))")
        lines.append("📅  Generated:   \(timestampFormatter.string(from: Date()))")
        lines.append("📊  Total:       \(chains.count) request chain(s)")
        lines.append("")
        lines.append("══════════════════════════════════════════════")
        lines.append("")

        for (i, chain) in chronological.enumerated() {
            lines.append("┌──────────────────────────────────────────────")
            lines.append("│  🔗  [\(i + 1)/\(chains.count)]  \(chain.tag)")
            lines.append("└──────────────────────────────────────────────")
            lines.append(exportChainBody(chain, insights: insights))
            lines.append("")
            lines.append("")
        }

        lines.append("══════════════════════════════════════════════")
        lines.append("              📋  END OF LOGS  📋              ")
        lines.append("══════════════════════════════════════════════")

        return lines.joined(separator: "\n")
    }

    // MARK: - Export Single Chain

    /// Produces a log file for a single chain, including device header and all attempts.
    static func exportChain(_ chain: APIRequestChain, insights: ChainBusinessInsights? = nil) -> String {
        var lines: [String] = []

        lines.append("╔══════════════════════════════════════════════╗")
        lines.append("║           🔗  REQUEST CHAIN LOG  🔗          ║")
        lines.append("╚══════════════════════════════════════════════╝")
        lines.append("")
        lines.append("📱  Device:      \(deviceInfo)")
        if let environment { lines.append("🌍  Environment: \(environment)") }
        lines.append("🏗️  Version:     \(appVersion) (\(buildNumber))")
        lines.append("📅  Generated:   \(timestampFormatter.string(from: Date()))")
        lines.append("🏷️  Tag:         \(chain.tag)")
        lines.append("")
        lines.append("══════════════════════════════════════════════")
        lines.append("")
        lines.append(exportChainBody(chain, insights: insights))
        lines.append("")
        lines.append("══════════════════════════════════════════════")
        lines.append("              📋  END OF LOG  📋               ")
        lines.append("══════════════════════════════════════════════")

        return lines.joined(separator: "\n")
    }

    // MARK: - Shared Chain Body

    /// Formats the summary stats and all attempts for a single chain.
    private static func exportChainBody(_ chain: APIRequestChain, insights: ChainBusinessInsights?) -> String {
        var lines: [String] = []

        let statusEmoji = chain.isResolved.value ? "✅" : "⏳"
        let httpCount = chain.attempts.value.filter { !$0.isExternalCompletion }.count

        lines.append("   \(statusEmoji)  Status:      \(chain.isResolved.value ? "Resolved" : "In flight")")
        lines.append("   ⏱️  Duration:    \(chain.totalDurationString)")
        lines.append("   🌐  HTTP:        \(httpCount) attempt(s)")
        lines.append("   🔔  External:    \(chain.externalCompletionCount) event(s)")
        lines.append("   ↩️  Fallbacks:   \(chain.fallbackCount)")
        for (label, value) in insights?.overviewRows(for: chain) ?? [] {
            lines.append("   •  \(label):  \(value)")
        }
        lines.append("")

        for (i, attempt) in chain.attempts.value.enumerated() {
            lines.append(formatAttempt(attempt, index: i + 1, total: chain.attempts.value.count))
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Format Single Attempt

    /// Renders one attempt with its type badge, timestamps, URL, headers, and bodies.
    private static func formatAttempt(_ attempt: AttemptDisplayable, index: Int, total: Int) -> String {
        var lines: [String] = []

        let typeEmoji = attempt.isExternalCompletion ? "🔔" : "🌐"
        let typeLabel = attempt.isExternalCompletion ? "EXTERNAL" : "HTTP"

        lines.append("   ┌─ \(typeEmoji)  \(typeLabel) Attempt \(index)/\(total): \(attempt.label)  \(attempt.outcome.badge)")
        lines.append("   │")
        lines.append("   │  🕐  Started:   \(timestampFormatter.string(from: attempt.startedAt))")
        lines.append("   │  ⏱️  Duration:  \(attempt.durationString)")

        if !attempt.isExternalCompletion {
            let method = attempt.requestHTTPMethod
            let url = attempt.requestURL
            lines.append("   │")
            lines.append("   │  🚀  \(method)  \(url)")

            // Request headers
            let reqHeaders = attempt.requestHeaders
            if !reqHeaders.isEmpty {
                lines.append("   │")
                lines.append("   │  📋  Request Headers:")
                for (key, value) in reqHeaders.sorted(by: { $0.key < $1.key }) {
                    lines.append("   │      \(key): \(value)")
                }
            }

            // Request body
            if let body = attempt.requestBody, !body.isEmpty {
                lines.append("   │")
                lines.append("   │  📦  Request Body:")
                let bodyStr = prettyJSON(body) ?? String(data: body, encoding: .utf8) ?? "<binary \(body.count) bytes>"
                for line in bodyStr.components(separatedBy: "\n") {
                    lines.append("   │      \(line)")
                }
            }

            // Response headers
            if let respHeaders = attempt.responseHeaders, !respHeaders.isEmpty {
                lines.append("   │")
                lines.append("   │  📋  Response Headers:")
                for (key, value) in respHeaders.sorted(by: { $0.key < $1.key }) {
                    lines.append("   │      \(key): \(value)")
                }
            }
        }

        // Response body
        if let responseBody = attempt.responseBody, !responseBody.isEmpty {
            lines.append("   │")
            lines.append("   │  📥  Response Body:")
            if let data = responseBody.data(using: .utf8) {
                let bodyStr = prettyJSON(data) ?? responseBody
                for line in bodyStr.components(separatedBy: "\n") {
                    lines.append("   │      \(line)")
                }
            } else {
                lines.append("   │      \(responseBody)")
            }
        }

        lines.append("   │")
        lines.append("   └──────────────────────────────────────")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    // MARK: - Export All (Markdown + <details>)

    /// Produces the full log as Markdown where every chain and attempt is wrapped
    /// in an HTML `<details>`/`<summary>` element, so blocks collapse when the file
    /// is previewed in a Markdown viewer or on GitHub.
    static func exportAllMarkdownCollapsible(chains: [APIRequestChain], insights: ChainBusinessInsights? = nil) -> String {
        let chronological = chains.reversed()
        var lines: [String] = []

        lines.append("# 📡 API Network Logs")
        lines.append("")
        lines.append("- **📱 Device:** \(deviceInfo)")
        if let environment { lines.append("- **🌍 Environment:** \(environment)") }
        lines.append("- **🏗️ Version:** \(appVersion) (\(buildNumber))")
        lines.append("- **📅 Generated:** \(timestampFormatter.string(from: Date()))")
        lines.append("- **📊 Total:** \(chains.count) request chain(s)")
        lines.append("")

        for (i, chain) in chronological.enumerated() {
            let statusEmoji = chain.isResolved.value ? "✅" : "⏳"
            let statusText = chain.isResolved.value ? "Resolved" : "In flight"
            lines.append("<details>")
            lines.append("<summary>🔗 [\(i + 1)/\(chains.count)] \(htmlEscape(chain.tag)) — \(statusEmoji) \(statusText)</summary>")
            lines.append("")
            lines.append(contentsOf: markdownChainStats(chain, insights: insights))
            lines.append("")
            for (j, attempt) in chain.attempts.value.enumerated() {
                let typeEmoji = attempt.isExternalCompletion ? "🔔" : "🌐"
                let typeLabel = attempt.isExternalCompletion ? "EXTERNAL" : "HTTP"
                lines.append("<details>")
                lines.append("<summary>\(typeEmoji) \(typeLabel) Attempt \(j + 1)/\(chain.attempts.value.count) — \(htmlEscape(attempt.label)) \(attempt.outcome.badge)</summary>")
                lines.append("")
                // The <summary> already labels the block; HTML code blocks so
                // bodies still render boxed inside <details>.
                lines.append(markdownAttempt(attempt))
                lines.append("</details>")
                lines.append("")
            }
            lines.append("</details>")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Markdown Builders

    /// Chain-level summary rows rendered as a Markdown bullet list.
    private static func markdownChainStats(_ chain: APIRequestChain, insights: ChainBusinessInsights?) -> [String] {
        let statusEmoji = chain.isResolved.value ? "✅" : "⏳"
        let httpCount = chain.attempts.value.filter { !$0.isExternalCompletion }.count
        var rows: [String] = []
        rows.append("- \(statusEmoji) **Status:** \(chain.isResolved.value ? "Resolved" : "In flight")")
        rows.append("- ⏱️ **Duration:** \(chain.totalDurationString)")
        rows.append("- 🌐 **HTTP:** \(httpCount) attempt(s)")
        rows.append("- 🔔 **External:** \(chain.externalCompletionCount) event(s)")
        rows.append("- ↩️ **Fallbacks:** \(chain.fallbackCount)")
        for (label, value) in insights?.overviewRows(for: chain) ?? [] {
            rows.append("- **\(label):** \(value)")
        }
        return rows
    }

    /// Renders one attempt's body as Markdown. The heading is omitted because
    /// the enclosing `<summary>` already labels the block.
    private static func markdownAttempt(_ attempt: AttemptDisplayable) -> String {
        var lines: [String] = []

        lines.append("- 🕐 **Started:** \(timestampFormatter.string(from: attempt.startedAt))")
        lines.append("- ⏱️ **Duration:** \(attempt.durationString)")

        if !attempt.isExternalCompletion {
            lines.append("- 🚀 **\(attempt.requestHTTPMethod)** `\(attempt.requestURL)`")

            let reqHeaders = attempt.requestHeaders
            if !reqHeaders.isEmpty {
                lines.append("")
                lines.append("**📋 Request Headers:**")
                lines.append(contentsOf: codeBlock(headerDump(reqHeaders), language: nil))
            }

            if let body = attempt.requestBody, !body.isEmpty {
                lines.append("")
                lines.append("**📦 Request Body:**")
                lines.append(contentsOf: bodyCodeBlock(for: body))
            }

            if let respHeaders = attempt.responseHeaders, !respHeaders.isEmpty {
                lines.append("")
                lines.append("**📋 Response Headers:**")
                lines.append(contentsOf: codeBlock(headerDump(respHeaders), language: nil))
            }
        }

        if let responseBody = attempt.responseBody, !responseBody.isEmpty {
            lines.append("")
            lines.append("**📥 Response Body:**")
            if let data = responseBody.data(using: .utf8) {
                lines.append(contentsOf: bodyCodeBlock(for: data, fallback: responseBody))
            } else {
                lines.append(contentsOf: codeBlock(responseBody, language: nil))
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// Sorted "key: value" dump of a headers dictionary.
    private static func headerDump(_ headers: [String: String]) -> String {
        headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
    }

    /// Wraps a body in a code block, using the `json` language hint when valid JSON.
    private static func bodyCodeBlock(for data: Data, fallback: String? = nil) -> [String] {
        if let pretty = prettyJSON(data) {
            return codeBlock(pretty, language: "json")
        }
        let text = fallback ?? String(data: data, encoding: .utf8) ?? "<binary \(data.count) bytes>"
        return codeBlock(text, language: nil)
    }

    /// Emits a `<pre><code>` block (preceded by a blank line). HTML rather
    /// than a Markdown fence because many renderers don't apply the boxed
    /// background to fences nested inside raw `<details>` HTML.
    private static func codeBlock(_ content: String, language: String?) -> [String] {
        let cls = language.map { " class=\"language-\($0)\"" } ?? ""
        return ["", "<pre><code\(cls)>\(htmlEscape(content))</code></pre>"]
    }

    /// Escapes the characters that would otherwise break out of an HTML text node.
    private static func htmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - Helpers

    /// Attempts to pretty-print `data` as JSON; returns `nil` if it's not valid JSON.
    private static func prettyJSON(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
              let string = String(data: pretty, encoding: .utf8) else { return nil }
        return string
    }

    static func writeTempFile(named name: String, content: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Bruno Collection Export (.bru files)

    /// Creates a Bruno collection directory with `bruno.json`, `collection.bru`,
    /// and one `.bru` file per chain (primary request only).
    /// Returns the directory URL ready to zip and share.
    static func exportBrunoCollection(chains: [ChainDisplayable]) -> URL {
        let collectionName = "Network_Logs_\(fileDateFormatter.string(from: Date()))"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(collectionName)

        // Clean previous export
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // bruno.json
        let meta: [String: Any] = [
            "version": "1",
            "name": collectionName,
            "type": "collection"
        ]
        if let data = try? JSONSerialization.data(withJSONObject: meta, options: .prettyPrinted) {
            try? data.write(to: dir.appendingPathComponent("bruno.json"))
        }

        // collection.bru — shared headers from the first primary attempt
        let firstPrimary = chains.lazy
            .compactMap { $0.attempts.value.first(where: { !$0.isExternalCompletion }) }
            .first
        let collectionBru = buildCollectionBru(sampleAttempt: firstPrimary)
        try? collectionBru.write(
            to: dir.appendingPathComponent("collection.bru"),
            atomically: true, encoding: .utf8
        )

        // One .bru file per unique tag (primary attempt only, deduplicated)
        var seenTags = Set<String>()
        var seq = 0
        for chain in chains {
            guard !seenTags.contains(chain.tag),
                  let primary = chain.attempts.value.first(where: { !$0.isExternalCompletion })
            else { continue }
            seenTags.insert(chain.tag)
            seq += 1
            let fileName = sanitizeFileName(chain.tag, index: seq)
            let bru = buildRequestBru(attempt: primary, name: chain.tag, seq: seq)
            let fileURL = dir.appendingPathComponent(fileName + ".bru")
            try? bru.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        return dir
    }

    // MARK: collection.bru

    /// Builds the `collection.bru` with shared headers, auth, and pre-request config.
    private static func buildCollectionBru(sampleAttempt: AttemptDisplayable?) -> String {
        var lines: [String] = []

        // headers block — from the sample attempt
        let headers = sampleAttempt?.requestHeaders.sorted { $0.key < $1.key } ?? []
        if !headers.isEmpty {
            lines.append("headers {")
            for (key, value) in headers {
                lines.append("  \(key): \(value)")
            }
            lines.append("}")
            lines.append("")
        }

        // auth block
        lines.append("auth {")
        lines.append("  mode: none")
        lines.append("}")
        lines.append("")

        // settings
        lines.append("settings {")
        lines.append("  encodeUrl: true")
        lines.append("  timeout: 0")
        lines.append("}")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    // MARK: Per-request .bru

    /// Renders a single request `.bru` file.
    /// URL is rewritten to `{{baseUrl}}/path`, query params get their own block,
    /// headers are inherited from `collection.bru`, and body uses 4-space indent.
    private static func buildRequestBru(attempt: AttemptDisplayable, name: String, seq: Int) -> String {
        let method = attempt.requestHTTPMethod.lowercased()
        let components = URLComponents(string: attempt.requestURL)
        let bruURL = buildBruURL(from: components)
        let hasBody = attempt.requestBody != nil && !attempt.requestBody!.isEmpty
        let bodyMode = hasBody ? "json" : "none"

        var lines: [String] = []

        // meta block
        lines.append("meta {")
        lines.append("  name: \(name)")
        lines.append("  type: http")
        lines.append("  seq: \(seq)")
        lines.append("}")
        lines.append("")

        // method block
        lines.append("\(method) {")
        lines.append("  url: \(bruURL)")
        lines.append("  body: \(bodyMode)")
        lines.append("  auth: inherit")
        lines.append("}")

        // params:query block
        if let queryItems = components?.queryItems, !queryItems.isEmpty {
            lines.append("")
            lines.append("params:query {")
            for item in queryItems {
                lines.append("  \(item.name): \(item.value ?? "")")
            }
            lines.append("}")
        }

        // body:json block
        if hasBody, let bodyData = attempt.requestBody {
            let bodyStr = prettyJSON(bodyData)
            ?? String(data: bodyData, encoding: .utf8)
            ?? ""
            lines.append("")
            lines.append("body:json {")
            for line in bodyStr.components(separatedBy: "\n") {
                lines.append("  \(line)")
            }
            lines.append("}")
        }

        // settings block
        lines.append("")
        lines.append("settings {")
        lines.append("  encodeUrl: true")
        lines.append("  timeout: 0")
        lines.append("}")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    /// Rewrites a full URL to `{{baseUrl}}/path?query` for Bruno variable substitution.
    private static func buildBruURL(from components: URLComponents?) -> String {
        guard let components = components else { return "{{baseUrl}}" }
        var path = components.path
        if path.hasPrefix("/") { path = String(path.dropFirst()) }

        var result = "{{baseUrl}}/\(path)"
        if let query = components.query, !query.isEmpty {
            result += "?\(query)"
        }
        return result
    }

    /// Makes a safe file name from a chain tag.
    private static func sanitizeFileName(_ tag: String, index: Int) -> String {
        let safe = tag
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: ".", with: "_")
        return "\(index)_\(safe)"
    }
}
