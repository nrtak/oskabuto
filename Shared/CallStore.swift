import Foundation

struct CallEntry: Codable, Identifiable {
    var id: Int64 { number }
    let number: Int64
    let label: String
    let blocked: Bool
}

enum CallStore {
    static let group = Bundle.main.object(forInfoDictionaryKey: "ProtectionAppGroup") as? String ?? "group.com.example.privacyguard"
    static var file: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("calls.json")
    }
    static func read() throws -> [CallEntry] {
        guard let file else { throw CocoaError(.fileNoSuchFile) }
        do { return try JSONDecoder().decode([CallEntry].self, from: Data(contentsOf: file)) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
    }
    static func write(_ entries: [CallEntry]) throws {
        guard let file else { throw CocoaError(.fileNoSuchFile) }
        let unique = Dictionary(entries.map { ($0.number, $0) }, uniquingKeysWith: { _, new in new })
        try JSONEncoder().encode(unique.values.sorted { $0.number < $1.number }).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
