import Foundation

// Incremental SSE framing: network chunks can split UTF-8 characters and lines.
// The completed response is authoritative; partial text never becomes feedback.
struct ResponseStream {
    private var line = Data()
    private var eventData = Data()
    private var received = 0
    private(set) var completed: Data?

    mutating func append(_ byte: UInt8) throws {
        received += 1
        guard received <= 1_000_000 else { throw AppError.message("Provider stream exceeded the size limit.") }
        if byte != 10 { line.append(byte); return }
        if line.last == 13 { line.removeLast() }
        defer { line.removeAll(keepingCapacity: true) }
        if line.isEmpty {
            try dispatch()
        } else if line.starts(with: Data("data:".utf8)) {
            var value = line.dropFirst(5)
            if value.first == 32 { value = value.dropFirst() }
            if !eventData.isEmpty { eventData.append(10) }
            eventData.append(contentsOf: value)
        }
    }
    private mutating func dispatch() throws {
        guard !eventData.isEmpty else { return }
        defer { eventData.removeAll(keepingCapacity: true) }
        if eventData == Data("[DONE]".utf8) { return }
        guard let event = try JSONSerialization.jsonObject(with: eventData) as? [String: Any],
              let type = event["type"] as? String else { throw AppError.message("Provider sent an invalid streaming event.") }
        switch type {
        case "response.completed":
            guard let response = event["response"] as? [String: Any], response["status"] as? String == "completed" else {
                throw AppError.message("Provider did not complete its answer.")
            }
            completed = try JSONSerialization.data(withJSONObject: response)
        case "response.failed", "response.incomplete", "error":
            throw AppError.message("Provider analysis failed or was incomplete. Check model access and usage limits; no partial answer was saved.")
        default: break
        }
    }
    func finish() throws -> Data {
        guard let completed else { throw AppError.message("Provider stream ended before response.completed. No partial answer was saved.") }
        return completed
    }
}
