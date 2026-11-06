import XCTest
@testable import ScreenSage

final class DiagnosticsTests: XCTestCase {
    func testPersistentReportContainsUsefulEventsWithoutSensitiveErrorData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = Diagnostics(directory: directory)
        log.record("provider.http", ["status": 400, "request": 12])
        log.record("provider.stream", ["text_deltas": 42, "terminal_items": 0])
        log.error("provider.error", NSError(domain: NSURLErrorDomain, code: -1001, userInfo: [NSLocalizedDescriptionKey: "secret-key private-prompt", NSURLErrorFailingURLStringErrorKey: "https://private.example/token"]))
        let report = log.report()
        XCTAssertTrue(report.contains("status=400"))
        XCTAssertTrue(report.contains("text_deltas=42"))
        XCTAssertTrue(report.contains("code=-1001"))
        XCTAssertFalse(report.contains("secret-key")); XCTAssertFalse(report.contains("private-prompt")); XCTAssertFalse(report.contains("private.example"))
        let reopened = Diagnostics(directory: directory)
        XCTAssertTrue(reopened.report().contains("text_deltas=42"))
        let file = try reopened.export()
        XCTAssertEqual(file.pathExtension, "txt")
        XCTAssertTrue(try String(contentsOf: file, encoding: .utf8).contains("status=400"))
        reopened.clear()
        XCTAssertFalse(reopened.report().contains("status=400"))
    }
    func testLoadingHistoryIsBoundedAndClearRemovesSavedHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let rows = (0..<1200).map { "synthetic event sequence=\($0)" }.joined(separator: "\n")
        try rows.write(to: directory.appendingPathComponent("events.txt"), atomically: true, encoding: .utf8)
        let log = Diagnostics(directory: directory)
        XCTAssertTrue(log.report().contains("Recent events: 1000/1000"))
        XCTAssertFalse(log.report().contains("sequence=199\n"))
        log.record("app.launch")
        XCTAssertTrue(log.report().contains("Recent events: 1000/1000"))
        log.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("events.txt").path))
    }
}
