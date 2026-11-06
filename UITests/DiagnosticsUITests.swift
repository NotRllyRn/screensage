import XCTest

final class DiagnosticsUITests: XCTestCase {
    func testPrepareDiagnosticsExposesShareableFile() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Diagnostics"].waitForExistence(timeout: 15))
        app.buttons["Diagnostics"].tap()
        XCTAssertTrue(app.buttons["Prepare diagnostics"].waitForExistence(timeout: 5))
        app.buttons["Prepare diagnostics"].tap()
        XCTAssertTrue(app.buttons["Share diagnostics text file"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Diagnostics prepared with recent events and current app state."].exists)
    }
}
