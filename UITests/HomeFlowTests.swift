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
        XCTAssertTrue(app.buttons["Check locally"].isEnabled, app.debugDescription)
        app.buttons["Check locally"].tap()
        let destination = app.staticTexts["resultDomain"]
        XCTAssertTrue(destination.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(destination.label, "example.org")
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
        XCTAssertTrue(app.buttons["Check locally"].isEnabled, app.debugDescription)
        app.buttons["Check locally"].tap()
        XCTAssertTrue(app.staticTexts["Unverified content"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(app.staticTexts["qrTextPreview"].label, "hello")
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts["Activity saving is off"].waitForExistence(timeout: 5))
    }

    func testPrivacyChecklistReview() {
        XCTAssertTrue(app.staticTexts["Safety Tools"].exists)
        XCTAssertTrue(app.staticTexts["Device Security"].exists)
        openHomeAction("Privacy Checks")
        openHomeAction("Cross-site tracking")
        let mark = app.buttons["Mark as reviewed"]
        XCTAssertTrue(mark.waitForExistence(timeout: 5))
        mark.tap()
        let undo = app.buttons["Undo review"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(mark.exists)
    }

    func testDeviceAndNetworkCardsReturnToHome() {
        let homeHeading = app.staticTexts["Kabuto Mobile Security"]
        for (action, screen) in [("Check this device", "Device Security"), ("Network Check", "Network Check")] {
            XCTAssertTrue(homeHeading.waitForExistence(timeout: 5))
            openHomeAction(action)
            let bar = app.navigationBars[screen]
            XCTAssertTrue(bar.waitForExistence(timeout: 5))
            bar.buttons.element(boundBy: 0).tap()
        }
        XCTAssertTrue(homeHeading.waitForExistence(timeout: 5))
    }

    func testOptingOutClearsSavedActivityAcrossLaunches() {
        app.tabBars.buttons["Settings"].tap()
        setActivitySavingDisabled(false)
        app.tabBars.buttons["Home"].tap()
        openHomeAction("Check a link")
        let field = app.descendants(matching: .any)["checkerInput"].firstMatch
        field.tap()
        field.typeText("https://example.org")
        app.buttons["Check locally"].tap()
        app.tabBars.buttons["Activity"].tap()
        let saved = app.descendants(matching: .any)["activitySummary"].firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(saved.label, "Link check: No local warning found")

        app.terminate()
        app.launchArguments = ["-welcomed", "YES"]
        app.launch()
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()
        setActivitySavingDisabled(true)
        app.terminate()
        app.launch()
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts["Activity saving is off"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()
        setActivitySavingDisabled(false)
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts["No checks saved yet"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()
        setActivitySavingDisabled(true)
    }

    private func setActivitySavingDisabled(_ disabled: Bool) {
        let toggle = app.switches["Don't Save Activity"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let expected = disabled ? "1" : "0"
        if toggle.value as? String != expected {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        XCTAssertEqual(toggle.value as? String, expected, app.debugDescription)
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

    func testProtectionReviewOpensEachCheck() {
        app.tabBars.buttons["Protection"].tap()
        openHomeAction("Protection Review")
        for (action, screen) in [("Check screen lock", "Device Security"), ("Review call filtering", "Call Protection"), ("Review browser privacy", "Privacy Checks")] {
            openHomeAction(action)
            let bar = app.navigationBars[screen]
            XCTAssertTrue(bar.waitForExistence(timeout: 5))
            bar.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars["Protection Review"].exists)
        }
    }

    func testMessageCheckExplainsTheWarning() {
        openHomeAction("Check a link or message")
        app.segmentedControls.buttons["Message"].tap()
        let input = app.descendants(matching: .any)["messageInput"].firstMatch
        input.tap()
        input.typeText("Urgent: send a gift card")
        app.buttons["Check message"].tap()
        XCTAssertTrue(app.staticTexts["Possible scam"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "gift card")).count > 0)
    }

    func testProvidersAreVisibleAndSelectable() {
        app.tabBars.buttons["Protection"].tap()
        openHomeAction("Web Protection")
        for provider in ["Quad9 Secure", "Cloudflare Malware Blocking", "Cloudflare 1.1.1.1", "Google Public DNS", "System Default", "Custom DNS"] {
            XCTAssertTrue(app.buttons[provider].exists, provider)
        }
        app.buttons["Google Public DNS"].tap()
        XCTAssertTrue(app.buttons["Google Public DNS"].isSelected)
    }

    func testWebProtectionKeepsInstallationGuidanceAfterCreatingProfile() {
        app.terminate()
        app.launchArguments += ["-dnsChoice", "Quad9 Secure"]
        app.launch()
        app.tabBars.buttons["Protection"].tap()
        openHomeAction("Web Protection")
        app.buttons["Create setup profile"].tap()
        XCTAssertTrue(app.staticTexts["Profile created"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Export setup profile"].exists)
        let installStep = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "tap Profile Downloaded")).firstMatch
        for _ in 0..<4 {
            if installStep.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(installStep.isHittable, app.debugDescription)
    }

    func testCustomDNSRejectsAnOutOfRangePort() {
        app.terminate()
        app.launchArguments += ["-dnsChoice", "Custom DNS", "-dnsCustom", "https://example.org:65536/dns-query"]
        app.launch()
        app.tabBars.buttons["Protection"].tap()
        openHomeAction("Web Protection")
        let create = app.buttons["Create setup profile"]
        for _ in 0..<3 {
            if create.isHittable { break }
            app.swipeUp()
        }
        create.tap()
        let alert = app.alerts["Kabuto"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "valid HTTPS DNS address")).firstMatch.exists)
        alert.buttons["OK"].tap()
        XCTAssertFalse(app.buttons["Export setup profile"].exists)
    }

    func testHomeWithLargeText() throws {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        try app.performAccessibilityAudit(for: [.textClipped, .contrast])
        let scan = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Scan a QR code")).firstMatch
        for _ in 0..<5 {
            if scan.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(scan.isHittable)
        scan.tap()
        XCTAssertTrue(app.navigationBars["QR Safety Scanner"].waitForExistence(timeout: 5))
    }
}
