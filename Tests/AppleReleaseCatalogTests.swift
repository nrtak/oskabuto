import XCTest
@testable import PrivacyGuardCore

final class AppleReleaseCatalogTests: XCTestCase {
    func testChoosesTheNewestPublicReleaseForTheExactDeviceAndDate() throws {
        let json = """
        {"PublicAssetSets":{"iOS":[
          {"ProductVersion":"18.9","SupportedDevices":["iPhone14,2"],"PostingDate":"2025-01-01"},
          {"ProductVersion":"18.10","SupportedDevices":["iPhone14,2"],"PostingDate":"2025-02-01","ExpirationDate":"2025-03-01"},
          {"ProductVersion":"18.11","SupportedDevices":["iPhone14,2"],"PostingDate":"2025-03-02"},
          {"ProductVersion":"19.0","SupportedDevices":["iPhone14,3"],"PostingDate":"2025-01-01"}
        ]}}
        """
        let catalog = try JSONDecoder().decode(AppleReleaseCatalog.self, from: Data(json.utf8))
        XCTAssertEqual(catalog.latestVersion(for: "iPhone14,2", on: "2025-03-01"), "18.10")
        XCTAssertEqual(catalog.latestVersion(for: "iPhone14,2", on: "2025-03-03"), "18.11")
        XCTAssertNil(catalog.latestVersion(for: "unknown", on: "2025-03-01"))
        XCTAssertNil(catalog.latestVersion(for: "iPhone14,2", on: "2024-12-31"))
        let expired = AppleReleaseCatalog(PublicAssetSets: .init(iOS: [catalog.PublicAssetSets.iOS[1]]))
        XCTAssertNil(expired.latestVersion(for: "iPhone14,2", on: "2025-03-02"))
    }
}
