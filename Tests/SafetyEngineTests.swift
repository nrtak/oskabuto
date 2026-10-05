import XCTest
@testable import PrivacyGuardCore

final class SafetyEngineTests: XCTestCase {
    func testOrdinaryHTTPSHasNoWarningButRemainsUnverified() {
        let result = SafetyEngine.check("https://example.com/path")
        XCTAssertFalse(result.suspicious)
        XCTAssertTrue(result.reasons.contains { $0.contains("cannot verify reputation") })
    }
    func testDisguisedDestination() {
        XCTAssertTrue(SafetyEngine.check("https://bank.example@evil.example").suspicious)
        XCTAssertTrue(SafetyEngine.check("http://example.com").suspicious)
        XCTAssertTrue(SafetyEngine.check("https://xn--lookalike.example").suspicious)
        XCTAssertTrue(SafetyEngine.check("https://127.0.0.1").suspicious)
    }
    func testQRCommandsNeverTreatedAsSafeLinks() {
        for value in ["WIFI:T:WPA;S:test;;", "javascript:alert(1)", "mailto:test@example.com", "", "not a url"] {
            XCTAssertTrue(SafetyEngine.check(value).suspicious)
        }
    }
    func testSMSRequiresMultipleSignals() {
        XCTAssertFalse(SafetyEngine.isJunk("Your appointment is tomorrow"))
        XCTAssertFalse(SafetyEngine.isJunk("Urgent: please call me"))
        XCTAssertFalse(SafetyEngine.isJunk("Visit https://example.com"))
        XCTAssertTrue(SafetyEngine.isJunk("Unpaid toll: pay now https://example.com"))
    }
}
