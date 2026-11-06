import XCTest
import UIKit
@testable import ScreenSage

final class ScreenSageTests: XCTestCase {
    func frame(_ time: TimeInterval, width: CGFloat = 30, height: CGFloat = 60) -> Frame {
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return Frame(image: image, date: Date(timeIntervalSince1970: time))
    }
    func testSamplingIsBoundedAndOrdered() {
        var window = FrameWindow()
        for time in 0..<75 { _ = window.append(frame(Double(time))) }
        XCTAssertEqual(window.accepted, 8)
        XCTAssertEqual(window.frames.count, 6)
        XCTAssertEqual(window.frames.map { $0.date.timeIntervalSince1970 }, [20, 30, 40, 50, 60, 70])
        XCTAssertFalse(window.append(frame(69)))
        window.clear(); XCTAssertTrue(window.frames.isEmpty); XCTAssertEqual(window.accepted, 0)
    }
    func testContactSheetHandlesRotationAndPartialBatch() {
        XCTAssertNil(ContactSheet.render([]))
        let data = ContactSheet.render([frame(0), frame(10, width: 60, height: 30)])!
        let image = UIImage(data: data)!
        XCTAssertEqual(image.size, CGSize(width: 1440, height: 3000))
        XCTAssertLessThan(data.count, 4_000_000)
        // Letterboxing keeps portrait/landscape images inside their own cells.
        let cg = image.cgImage!
        let pixels = UnsafeMutablePointer<UInt8>.allocate(capacity: 1440 * 3000 * 4)
        defer { pixels.deallocate() }
        let context = CGContext(data: pixels, width: 1440, height: 3000, bitsPerComponent: 8, bytesPerRow: 1440 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 1440, height: 3000))
        XCTAssertGreaterThan(pixels[(500 * 1440 + 360) * 4], 200)
        XCTAssertLessThan(pixels[(1500 * 1440 + 360) * 4], 20)
    }
    func testEndpointValidationAndJoining() throws {
        var c = Connection(); c.address = "https://example.com/proxy/v1/"
        XCTAssertEqual(try c.endpoint("chat/completions").absoluteString, "https://example.com/proxy/v1/chat/completions")
        for bad in ["http://example.com", "https://user:secret@example.com", "https://example.com?v=1", "https://example.com/#secret", "relative"] {
            c.address = bad; XCTAssertThrowsError(try c.endpoint("responses"))
        }
    }
    func testBothWireFormatsCarryImageAndBoundOutput() {
        var c = Connection(); c.model = "vision-test"
        let image = Data([1, 2, 3])
        let chat = Provider.body(connection: c, prompt: "goal", image: image)
        XCTAssertEqual(chat["max_tokens"] as? Int, 600)
        XCTAssertTrue(String(data: try! JSONSerialization.data(withJSONObject: chat), encoding: .utf8)!.contains("data:image"))
        c.wire = .responses
        let responses = Provider.body(connection: c, prompt: "goal", image: image)
        XCTAssertEqual(responses["store"] as? Bool, false)
        XCTAssertNotNil(responses["input"])
        c.kind = .chatGPT
        let bridge = Provider.body(connection: c, prompt: "goal", image: image)
        XCTAssertEqual(bridge["image"] as? String, "data:image/jpeg;base64,AQID")
    }
    func testProviderRequiresCompletedNonemptyText() throws {
        var c = Connection()
        let ok = Data(#"{"choices":[{"finish_reason":"stop","message":{"content":"blue"}}]}"#.utf8)
        XCTAssertEqual(try Provider.parse(ok, connection: c), "blue")
        let truncated = Data(#"{"choices":[{"finish_reason":"length","message":{"content":"partial"}}]}"#.utf8)
        XCTAssertThrowsError(try Provider.parse(truncated, connection: c))
        c.wire = .responses
        XCTAssertThrowsError(try Provider.parse(Data(#"{"status":"incomplete","output":[]}"#.utf8), connection: c))
        let response = Data(#"{"status":"completed","output":[{"content":[{"type":"output_text","text":"done"}]}]}"#.utf8)
        XCTAssertEqual(try Provider.parse(response, connection: c), "done")
    }
    @MainActor func testStopClearsConsentIndependentContextAndCancelsWork() async {
        let session = Session(); session.goal = "Synthetic task"; session.history = [Feedback(text: "old")]
        session.stop()
        XCTAssertTrue(session.history.isEmpty); XCTAssertFalse(session.active); XCTAssertFalse(session.busy)
        XCTAssertEqual(session.frameCount, 0); XCTAssertNil(session.lastFrame)
        await Task.yield()
    }
    @MainActor func testAlertExcerptAndNamedContextEditing() {
        XCTAssertEqual(Session.excerpt("ALERT: Missing units\nWhy it matters: check dimensions"), "Missing units")
        XCTAssertEqual(Session.excerpt("ALERT: " + String(repeating: "x", count: 300)).count, 140)
        let saved = UserDefaults.standard.data(forKey: "monitoringPresets")
        let selected = UserDefaults.standard.string(forKey: "selectedPresetID")
        defer {
            UserDefaults.standard.set(saved, forKey: "monitoringPresets")
            UserDefaults.standard.set(selected, forKey: "selectedPresetID")
        }
        let session = Session()
        var preset = MonitoringPreset(name: "Studying", instructions: "Interrupt when my equations lose their units.")
        session.savePreset(preset)
        XCTAssertEqual(session.currentPreset, preset)
        preset.instructions = "Also check sign errors."
        session.savePreset(preset)
        XCTAssertEqual(MonitoringPreset.load().first(where: { $0.id == preset.id })?.instructions, preset.instructions)
        session.deletePresets(IndexSet(integersIn: 0..<session.presets.count))
        XCTAssertEqual(session.presets.count, 1)
        XCTAssertEqual(session.currentPreset.name, "Default")
    }

}
