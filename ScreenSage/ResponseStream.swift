import Foundation

// Keep streamed text by output/content index. Done events replace deltas, never
// append duplicates. A successful terminal event is still required for feedback.
struct ResponseStream {
    private var line = Data()
    private var eventData = Data()
    private var parts: [Int: [Int: String]] = [:]
    private var commentary: Set<Int> = []
    private(set) var received = 0
    private(set) var events = 0
    private(set) var deltas = 0
    private(set) var textDone = 0
    private(set) var itemsDone = 0
    private(set) var terminalItems = 0
    private(set) var terminalStatus = 0
    private(set) var usedStreamText = false
    private(set) var completed: Data?
    var diagnosticCounts: [String: Int] {
        ["terminal_status": terminalStatus, "bytes": received, "events": events, "text_deltas": deltas, "text_done": textDone,
         "items_done": itemsDone, "terminal_items": terminalItems, "stream_fallback": usedStreamText ? 1 : 0,
         "text_parts": parts.values.reduce(0) { $0 + $1.count }, "completed": completed == nil ? 0 : 1]
    }
    mutating func append(_ byte: UInt8) throws {
        received += 1
        guard received <= 1_000_000 else { throw AppError.message("Provider stream exceeded the size limit.") }
        if byte != 10 { line.append(byte); return }
        if line.last == 13 { line.removeLast() }
        defer { line.removeAll(keepingCapacity: true) }
        if line.isEmpty { try dispatch() }
        else if line.starts(with: Data("data:".utf8)) {
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
        events += 1
        let outputIndex = event["output_index"] as? Int ?? 0
        let contentIndex = event["content_index"] as? Int ?? 0
        switch type {
        case "response.output_text.delta":
            deltas += 1
            if let text = event["delta"] as? String { parts[outputIndex, default: [:]][contentIndex, default: ""] += text }
        case "response.output_text.done":
            textDone += 1
            if let text = event["text"] as? String { parts[outputIndex, default: [:]][contentIndex] = text }
        case "response.content_part.done":
            if let part = event["part"] as? [String: Any], part["type"] as? String == "output_text", let text = part["text"] as? String {
                parts[outputIndex, default: [:]][contentIndex] = text
            }
        case "response.output_item.added", "response.output_item.done":
            guard let item = event["item"] as? [String: Any], item["type"] as? String == "message" else { break }
            if item["phase"] as? String == "commentary" { commentary.insert(outputIndex) }
            else if item["phase"] as? String == "final_answer" { commentary.remove(outputIndex) }
            if type == "response.output_item.done" {
                itemsDone += 1
                for (index, part) in (item["content"] as? [[String: Any]] ?? []).enumerated() {
                    if part["type"] as? String == "output_text", let text = part["text"] as? String { parts[outputIndex, default: [:]][index] = text }
                }
            }
        case "response.completed":
            terminalStatus = 1
            guard var response = event["response"] as? [String: Any], response["status"] as? String == "completed" else {
                throw AppError.message("Provider did not complete its answer.")
            }
            let output = response["output"] as? [[String: Any]] ?? []
            terminalItems = output.count
            if Self.text(in: output).isEmpty {
                let text = parts.keys.sorted().filter { !commentary.contains($0) }.flatMap { index in
                    (parts[index] ?? [:]).sorted { $0.key < $1.key }.map(\.value)
                }.joined(separator: "\n")
                usedStreamText = !text.isEmpty
                response["output"] = [["type": "message", "role": "assistant", "content": [["type": "output_text", "text": text]]]]
            }
            completed = try JSONSerialization.data(withJSONObject: response)
        case "response.failed", "response.incomplete", "error":
            terminalStatus = type == "response.failed" ? 2 : type == "response.incomplete" ? 3 : 4
            throw AppError.message("Provider analysis failed or was incomplete. Check model access and usage limits; no partial answer was saved.")
        default: break
        }
    }
    static func text(in output: [[String: Any]]) -> String {
        output.filter { $0["phase"] as? String != "commentary" }
            .flatMap { $0["content"] as? [[String: Any]] ?? [] }
            .filter { $0["type"] as? String == "output_text" }
            .compactMap { $0["text"] as? String }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func finish() throws -> Data {
        guard let completed else { throw AppError.message("Provider stream ended before response.completed. No partial answer was saved.") }
        return completed
    }
}
