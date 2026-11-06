import XCTest
@testable import ScreenSage

final class ResponseStreamTests: XCTestCase {
    let completed = #"{"type":"response.completed","response":{"status":"completed","output":[{"content":[{"type":"output_text","text":"ALERT: Check units ✓"}]}]}}"#
    func feed(_ text: String, to stream: inout ResponseStream) throws {
        for byte in text.utf8 { try stream.append(byte) }
    }
    func testBytewiseUTF8AndCRLFWithCommentsAndPartialText() throws {
        var stream = ResponseStream()
        try feed(": keepalive\r\n\r\nevent: response.output_text.delta\r\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\"wrong partial\"}\r\n\r\n", to: &stream)
        XCTAssertThrowsError(try stream.finish())
        try feed("event: response.completed\r\ndata: " + completed + "\r\n\r\n", to: &stream)
        var connection = Connection(); connection.wire = .responses
        XCTAssertEqual(try Provider.parse(stream.finish(), connection: connection), "ALERT: Check units ✓")
    }
    func testMultilineEventData() throws {
        var stream = ResponseStream()
        let multiline = completed.replacingOccurrences(of: ",\"response\"", with: ",\ndata: \"response\"")
        try feed("data: " + multiline + "\n\n", to: &stream)
        XCTAssertNotNil(try stream.finish())
    }
    func testFailuresAndPrematureEOFNeverAcceptPartialAnswers() throws {
        for type in ["response.failed", "response.incomplete", "error"] {
            var stream = ResponseStream()
            XCTAssertThrowsError(try feed("data: {\"type\":\"\(type)\"}\n\n", to: &stream))
        }
        var stream = ResponseStream()
        try feed("data: [DONE]\n\n", to: &stream)
        XCTAssertThrowsError(try stream.finish())
        XCTAssertThrowsError(try feed("data: invalid-json\n\n", to: &stream))
    }
    func testStreamHasSizeLimitEvenWithoutNewlines() {
        var stream = ResponseStream()
        XCTAssertThrowsError(try feed(String(repeating: "x", count: 1_000_001), to: &stream))
    }
    func testHTTPErrorDetailIsBoundedAndRedactsConnectionKey() {
        let data = Data(#"{"error":{"message":"Unsupported parameter: max_output_tokens; test-secret"}}"#.utf8)
        let message = Provider.httpError(status: 400, data: data, key: "test-secret").localizedDescription
        XCTAssertTrue(message.contains("max_output_tokens"))
        XCTAssertFalse(message.contains("test-secret"))
        XCTAssertTrue(message.contains("HTTP 400"))
    }
    func decode(_ events: [[String: Any]]) throws -> String {
        var stream = ResponseStream()
        for event in events {
            let json = String(data: try JSONSerialization.data(withJSONObject: event), encoding: .utf8)!
            try feed("data: " + json + "\n\n", to: &stream)
        }
        var connection = Connection(); connection.wire = .responses
        return try Provider.parse(stream.finish(), connection: connection)
    }
    var emptyCompletion: [String: Any] { ["type": "response.completed", "response": ["status": "completed", "output": []]] }
    func testDeltaAnswerSurvivesEmptyCompletionForAllRequestKinds() throws {
        for answer in ["Blue", "NOTE: Six frames reviewed", "Answer to your question"] {
            XCTAssertEqual(try decode([
                ["type": "response.output_text.delta", "output_index": 0, "content_index": 0, "delta": answer], emptyCompletion
            ]), answer)
        }
    }
    func testDoneEventsReplaceDeltasWithoutDuplicatingText() throws {
        XCTAssertEqual(try decode([
            ["type": "response.output_text.delta", "delta": "Bl"],
            ["type": "response.output_text.delta", "delta": "ue"],
            ["type": "response.output_text.done", "text": "Blue"],
            ["type": "response.content_part.done", "part": ["type": "output_text", "text": "Blue"]],
            ["type": "response.output_item.done", "item": ["type": "message", "content": [["type": "output_text", "text": "Blue"]]]],
            emptyCompletion
        ]), "Blue")
    }
    func testItemOnlyAnswerAndCommentaryFiltering() throws {
        XCTAssertEqual(try decode([
            ["type": "response.output_item.done", "output_index": 0, "item": ["type": "message", "phase": "commentary", "content": [["type": "output_text", "text": "Working…"]]]],
            ["type": "response.output_item.done", "output_index": 1, "item": ["type": "message", "phase": "final_answer", "content": [["type": "output_text", "text": "Blue"]]]],
            emptyCompletion
        ]), "Blue")
    }
    func testIndexedPartsStayOrderedAndBrokerNoticeDoesNotHideAlerts() throws {
        XCTAssertEqual(try decode([
            ["type": "response.output_text.done", "output_index": 0, "content_index": 1, "text": "Why: check dimensions."],
            ["type": "response.output_text.done", "output_index": 0, "content_index": 0, "text": "🔨 Example usage notice\n\nALERT: Missing units"],
            emptyCompletion
        ]), "ALERT: Missing units\nWhy: check dimensions.")
    }
    func testDeltasCannotBecomeAnAnswerWithoutSuccessfulCompletion() throws {
        var stream = ResponseStream()
        try feed("data: {\"type\":\"response.output_text.delta\",\"delta\":\"Blue\"}\n\n", to: &stream)
        XCTAssertThrowsError(try stream.finish())
        XCTAssertThrowsError(try feed("data: {\"type\":\"response.failed\"}\n\n", to: &stream))
        XCTAssertEqual(stream.diagnosticCounts["terminal_status"], 2)
    }

}
