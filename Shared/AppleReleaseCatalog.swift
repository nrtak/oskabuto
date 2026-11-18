import Foundation

struct AppleReleaseCatalog: Decodable {
    struct Platforms: Decodable { let iOS: [Release] }
    struct Release: Decodable {
        let ProductVersion: String
        let SupportedDevices: [String]
        let PostingDate: String
        let ExpirationDate: String?
    }
    let PublicAssetSets: Platforms

    func latestVersion(for model: String, on today: String) -> String? {
        PublicAssetSets.iOS.filter {
            $0.SupportedDevices.contains(model) && $0.PostingDate <= today &&
            ($0.ExpirationDate.map { $0 >= today } ?? true)
        }.map(\.ProductVersion).max { $0.compare($1, options: .numeric) == .orderedAscending }
    }
}
