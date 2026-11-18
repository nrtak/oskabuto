import XCTest

final class HomeFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-welcomed", "YES", "-dontSave", "YES"]
        app.launch()
    }

    private func openHomeAction(_ title: String) {
        let button = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", title)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 6), title)
        button.tap()
    }

    func testEditingLinkRemovesPreviousResult() {
        openHomeAction("Check a link")
        let field = app.descendants(matching: .any)["checkerInput"].firstMatch
        field.tap()
        field.typeText("https://example.org")
        app.buttons["Check locally"].tap()
        let destination = app.staticTexts["Destination: example.org"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("a")
        XCTAssertFalse(destination.exists)
    }

    func testManualQRAndPrivateActivity() {
        openHomeAction("Scan a QR code")
        app.buttons["Scan with camera"].tap()
        let manual = app.buttons["Enter QR contents"]
        XCTAssertTrue(manual.waitForExistence(timeout: 6))
        manual.tap()
        let field = app.descendants(matching: .any)["checkerInput"].firstMatch
        field.tap()
        field.typeText("hello")
        app.buttons["Check locally"].tap()
        XCTAssertTrue(app.staticTexts["Unverified content"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts["Activity saving is off"].waitForExistence(timeout: 5))
    }

    func testProtectionAndSettingsNavigation() {
        app.tabBars.buttons["Protection"].tap()
        for (name, destination) in [("Call Protection", "Call Protection"), ("Message Filter", "Message Filter"), ("Web Protection", "Web Protection")] {
            openHomeAction(name)
            XCTAssertTrue(app.navigationBars[destination].waitForExistence(timeout: 5))
            if name == "Call Protection" { XCTAssertTrue(app.buttons["Open call blocking settings"].exists) }
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.switches["Don't Save Activity"].exists)
    }
}
