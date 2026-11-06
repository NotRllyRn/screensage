import Foundation
import Security

enum ConnectionKind: String, Codable, CaseIterable { case custom = "Custom provider", chatGPT = "Codex · ChatGPT sign-in" }
enum WireProtocol: String, Codable, CaseIterable { case chat = "Chat Completions", responses = "Responses" }
struct Connection: Codable {
    var kind = ConnectionKind.custom
    var address = ""
    var key = ""
    var model = ""
    var wire = WireProtocol.chat
    func endpoint(_ path: String) throws -> URL {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw AppError.message("Enter an HTTPS base URL without credentials, query or fragment.") }
        return url.appendingPathComponent(path)
    }
    func validate() throws {
        _ = try endpoint("")
        guard !key.isEmpty, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError.message("Enter the connection key and a vision model name.") }
    }
}
enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}
enum Vault {
    static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ScreenSage", kSecAttrAccount as String: "connection"]
    static func load() -> Connection {
        var q = query; q[kSecReturnData as String] = true
        var value: CFTypeRef?
        let result = SecItemCopyMatching(q as CFDictionary, &value)
        Diagnostics.shared.record("keychain.load", ["status": Int(result)])
        guard result == errSecSuccess, let data = value as? Data else { return Connection() }
        return (try? JSONDecoder().decode(Connection.self, from: data)) ?? Connection()
    }
    static func save(_ connection: Connection) throws {
        let data = try JSONEncoder().encode(connection)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound { result = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) }
        Diagnostics.shared.record("keychain.save", ["status": Int(result)])
        guard result == errSecSuccess else { throw AppError.message("Keychain could not save this connection (\(result)).") }
    }
}

// Reject redirects so bearer credentials and images never follow an unexpected host.
final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
enum Provider {
    static func body(connection: Connection, prompt: String, image: Data) -> [String: Any] {
        let uri = "data:image/jpeg;base64," + image.base64EncodedString()
        if connection.kind == .chatGPT { return ["model": connection.model, "prompt": prompt, "image": uri] }
        if connection.wire == .chat {
            return ["model": connection.model, "messages": [["role": "user", "content": [["type": "text", "text": prompt], ["type": "image_url", "image_url": ["url": uri]]]]], "max_tokens": 600, "stream": false]
        }
        return ["model": connection.model, "input": [["role": "user", "content": [["type": "input_text", "text": prompt], ["type": "input_image", "image_url": uri]]]], "store": false, "stream": true]
    }
    static func analyze(connection: Connection, prompt: String, image: Data) async throws -> String {
        let requestID = Int.random(in: 1...Int(Int32.max))
        let started = Date()
        var stage = 0
        Diagnostics.shared.record("provider.request", ["request": requestID, "companion": connection.kind == .chatGPT ? 1 : 0, "responses": connection.wire == .responses ? 1 : 0, "image_bytes": image.count, "prompt_characters": prompt.count])
        defer { Diagnostics.shared.record("provider.finished", ["request": requestID, "stage": stage, "elapsed_ms": Int(Date().timeIntervalSince(started) * 1000), "cancelled": Task.isCancelled ? 1 : 0]) }
        do {
            try connection.validate()
            let path = connection.kind == .chatGPT ? "analyze" : (connection.wire == .chat ? "chat/completions" : "responses")
            var request = URLRequest(url: try connection.endpoint(path)); request.httpMethod = "POST"; request.timeoutInterval = 90
            request.setValue("Bearer " + connection.key, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body(connection: connection, prompt: prompt, image: image))
            let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForResource = 95; config.httpCookieStorage = nil; config.urlCache = nil
            let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            stage = 1
            let (bytes, response) = try await session.bytes(for: request)
            stage = 2
            guard let http = response as? HTTPURLResponse else { throw AppError.message("Invalid provider response.") }
            Diagnostics.shared.record("provider.http", ["request": requestID, "status": http.statusCode, "sse": http.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true ? 1 : 0])
            guard (200..<300).contains(http.statusCode) else {
                var detail = Data()
                for try await byte in bytes {
                    try Task.checkCancellation()
                    if detail.count >= 16_384 { break }
                    detail.append(byte)
                }
                throw httpError(status: http.statusCode, data: detail, key: connection.key)
            }
            if connection.kind == .custom && connection.wire == .responses {
                guard http.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true else {
                    throw AppError.message("Expected a streaming Responses reply (text/event-stream). Check the provider API format.")
                }
                stage = 3
                var stream = ResponseStream()
                defer { Diagnostics.shared.record("provider.stream", stream.diagnosticCounts.merging(["request": requestID]) { _, new in new }) }
                for try await byte in bytes {
                    try Task.checkCancellation()
                    try stream.append(byte)
                    if stream.completed != nil { break }
                }
                let result = try parse(stream.finish(), connection: connection)
                stage = 5
                Diagnostics.shared.record("provider.success", ["request": requestID, "characters": result.count])
                return result
            }
            stage = 4
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 1_000_000 else { throw AppError.message("Provider response exceeded the size limit.") }
                data.append(byte)
            }
            let result = try parse(data, connection: connection)
            stage = 5
            Diagnostics.shared.record("provider.success", ["request": requestID, "characters": result.count])
            return result
        } catch {
            Diagnostics.shared.error("provider.error", error)
            throw error
        }
    }
    static func httpError(status: Int, data: Data, key: String) -> AppError {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let error = json?["error"] as? [String: Any]
        var message = error?["message"] as? String ?? json?["detail"] as? String ?? "Check authorization, model, quota and endpoint."
        let lower = message.lowercased()
        Diagnostics.shared.record("provider.http_rejection", ["status": status, "structured_error": error == nil ? 0 : 1,
            "mentions_stream": lower.contains("stream") ? 1 : 0, "mentions_output_limit": lower.contains("max_output_tokens") ? 1 : 0,
            "mentions_model": lower.contains("model") ? 1 : 0, "mentions_image": lower.contains("image") ? 1 : 0,
            "mentions_instructions": lower.contains("instructions") ? 1 : 0, "mentions_quota": lower.contains("quota") ? 1 : 0])
        if !key.isEmpty { message = message.replacingOccurrences(of: key, with: "[redacted]") }
        return .message("Provider HTTP \(status): \(String(message.prefix(400))) No automatic retry.")
    }
    static func parse(_ data: Data, connection: Connection) throws -> String {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        var text: String?
        if connection.kind == .chatGPT {
            text = json["text"] as? String
            if let id = json["threadId"] as? String { text = text.map { $0 + "\n\nCodex thread: " + String(id.prefix(100)) } }
        }
        else if connection.wire == .chat {
            let first = (json["choices"] as? [[String: Any]])?.first
            guard first?["finish_reason"] as? String == "stop" else { throw AppError.message("Provider did not complete its answer.") }
            text = (first?["message"] as? [String: Any])?["content"] as? String
        } else {
            guard json["status"] as? String == "completed" else { throw AppError.message("Provider did not complete its answer.") }
            let output = json["output"] as? [[String: Any]] ?? []
            text = ResponseStream.text(in: output)
            Diagnostics.shared.record("provider.parsed_shape", ["output_items": output.count, "text_characters": text?.count ?? 0,
                "refusal_parts": output.flatMap { $0["content"] as? [[String: Any]] ?? [] }.filter { $0["type"] as? String == "refusal" }.count])
            // Codex Broker prepends a usage notice to final answers. Keep it out
            // of task context and ALERT classification, without logging its text.
            if let value = text, value.hasPrefix("🔨 "), let newline = value.firstIndex(of: "\n") {
                text = String(value[value.index(after: newline)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                Diagnostics.shared.record("provider.broker_notice_removed")
            }
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Diagnostics.shared.record("provider.empty_text")
            throw AppError.message("Provider completed without readable answer text. Prepare diagnostics to inspect the stream event counts.")
        }
        return String(text.prefix(6000))
    }
}
