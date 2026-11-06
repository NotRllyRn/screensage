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
}
