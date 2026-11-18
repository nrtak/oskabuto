import XCTest
@testable import PrivacyGuardCore

final class SafetyEngineTests: XCTestCase {
    func testOrdinaryHTTPSHasNoWarningButRemainsUnverified() {
        let result = SafetyEngine.check("https://example.com/path")
        XCTAssertFalse(result.suspicious)
        XCTAssertEqual(result.destination, "example.com")
        XCTAssertTrue(result.reasons.isEmpty)
    }
    func testDisguisedDestination() {
        let disguised = SafetyEngine.check("https://bank.example@evil.example")
        XCTAssertTrue(disguised.suspicious)
        XCTAssertEqual(disguised.destination, "evil.example")
        XCTAssertTrue(disguised.reasons.contains { $0.contains("credentials") })
        XCTAssertTrue(SafetyEngine.check("http://example.com").suspicious)
        XCTAssertTrue(SafetyEngine.check("https://xn--lookalike.example").suspicious)
        XCTAssertTrue(SafetyEngine.check("https://127.0.0.1").suspicious)
    }
    func testQRCommandsNeverTreatedAsSafeLinks() {
        for value in ["WIFI:T:WPA;S:test;;", "javascript:alert(1)", "mailto:test@example.com", "", "not a url"] {
            let result = SafetyEngine.check(value)
            XCTAssertTrue(result.suspicious)
            XCTAssertNil(result.destination)
        }
    }
    func testSMSRequiresMultipleSignals() {
        XCTAssertFalse(SafetyEngine.isJunk("Your appointment is tomorrow"))
        XCTAssertFalse(SafetyEngine.isJunk("Urgent: please call me"))
        XCTAssertFalse(SafetyEngine.isJunk("Visit https://example.com"))
        XCTAssertTrue(SafetyEngine.isJunk("Unpaid toll: pay now https://example.com"))
    }

    func testMessageCheckExplainsTheFilterDecision() {
        let message = "URGENT: Send a gift card immediately."
        let check = SafetyEngine.checkMessage(message)
        XCTAssertEqual(check.urgency, "urgent")
        XCTAssertEqual(check.request, "gift card")
        XCTAssertTrue(check.advice.contains("phone number"))
        XCTAssertEqual(check.matchesJunkRule, SafetyEngine.isJunk(message))
        let ordinary = SafetyEngine.checkMessage("Lunch is at noon.")
        XCTAssertNil(ordinary.request)
        XCTAssertNil(ordinary.urgency)
        XCTAssertFalse(ordinary.matchesJunkRule)
    }
}
