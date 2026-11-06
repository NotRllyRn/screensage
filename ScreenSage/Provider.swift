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
        guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return Connection() }
        return (try? JSONDecoder().decode(Connection.self, from: data)) ?? Connection()
    }
    static func save(_ connection: Connection) throws {
        let data = try JSONEncoder().encode(connection)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound { result = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) }
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
        try connection.validate()
        let path = connection.kind == .chatGPT ? "analyze" : (connection.wire == .chat ? "chat/completions" : "responses")
        var request = URLRequest(url: try connection.endpoint(path)); request.httpMethod = "POST"; request.timeoutInterval = 90
        request.setValue("Bearer " + connection.key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body(connection: connection, prompt: prompt, image: image))
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForResource = 95; config.httpCookieStorage = nil; config.urlCache = nil
        let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppError.message("Invalid provider response.") }
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
            var stream = ResponseStream()
            for try await byte in bytes {
                try Task.checkCancellation()
                try stream.append(byte)
                if stream.completed != nil { break }
            }
            return try parse(stream.finish(), connection: connection)
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 1_000_000 else { throw AppError.message("Provider response exceeded the size limit.") }
            data.append(byte)
        }
        return try parse(data, connection: connection)
    }
    static func httpError(status: Int, data: Data, key: String) -> AppError {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let error = json?["error"] as? [String: Any]
        var message = error?["message"] as? String ?? json?["detail"] as? String ?? "Check authorization, model, quota and endpoint."
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
            text = (json["output"] as? [[String: Any]])?.flatMap { $0["content"] as? [[String: Any]] ?? [] }.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError.message("Provider returned no text.") }
        return String(text.prefix(6000))
    }
}
