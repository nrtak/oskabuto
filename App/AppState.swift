import SwiftUI
import CallKit
import UserNotifications

struct ActivityItem: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    let summary: String
}

@MainActor final class AppState: ObservableObject {
    @Published var activities: [ActivityItem] = []
    @Published var calls: [CallEntry] = []
    @Published var callStatus = "Not yet checked"
    @Published var notice = ""
    @Published var dontSave: Bool { didSet {
        UserDefaults.standard.set(dontSave, forKey: "dontSave")
        if dontSave { activities = []; persist() }
    } }
    @Published var cadence: Int { didSet { UserDefaults.standard.set(cadence, forKey: "cadence") } }
    private let activityURL: URL
    static let extensionID = "com.example.privacyguard.CallDirectory"

    init() {
        dontSave = UserDefaults.standard.object(forKey: "dontSave") as? Bool ?? true
        cadence = UserDefaults.standard.object(forKey: "cadence") as? Int ?? 7
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
        activityURL = directory.appendingPathComponent("activity.json")
        if !dontSave, let data = try? Data(contentsOf: activityURL), let saved = try? JSONDecoder().decode([ActivityItem].self, from: data) { activities = saved }
        else { try? FileManager.default.removeItem(at: activityURL) }
        calls = (try? CallStore.read()) ?? []
    }
    func record(_ summary: String) {
        guard !dontSave else { return }
        activities.insert(.init(summary: summary), at: 0)
        activities = Array(activities.prefix(100)); persist()
    }
    func clear() { activities = []; persist() }
    private func persist() {
        do {
            if dontSave { if FileManager.default.fileExists(atPath: activityURL.path) { try FileManager.default.removeItem(at: activityURL) } }
            else { try JSONEncoder().encode(activities).write(to: activityURL, options: [.atomic, .completeFileProtection]) }
        } catch { notice = "Could not update local activity: \(error.localizedDescription)" }
    }
    func refreshCalls() {
        CXCallDirectoryManager.sharedInstance.getEnabledStatusForExtension(withIdentifier: Self.extensionID) { status, error in
            Task { @MainActor in
                self.callStatus = error.map { "Unavailable: \($0.localizedDescription)" } ?? (status == .enabled ? "Verified: extension enabled" : status == .disabled ? "Verified: extension disabled" : "Unknown")
            }
        }
    }
    func saveCalls(_ entries: [CallEntry]) {
        do {
            try CallStore.write(entries); calls = entries
            CXCallDirectoryManager.sharedInstance.reloadExtension(withIdentifier: Self.extensionID) { error in
                Task { @MainActor in self.notice = error.map { "Saved locally; reload failed: \($0.localizedDescription)" } ?? "Call list reloaded"; self.refreshCalls() }
            }
        } catch { notice = "Call list not saved: \(error.localizedDescription)" }
    }
    func scheduleReview() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["protection-review"])
        guard cadence > 0 else { notice = "Review reminders off"; return }
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else { notice = "Guided: allow notifications in Settings for reminders"; return }
            let content = UNMutableNotificationContent()
            content.title = "Protection Review"; content.body = "Review call filtering, DNS, and device privacy settings."; content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(cadence) * 86400, repeats: true)
            try await center.add(.init(identifier: "protection-review", content: content, trigger: trigger))
            notice = "Review scheduled every \(cadence) days"
        } catch { notice = "Reminder failed: \(error.localizedDescription)" }
    }
}
