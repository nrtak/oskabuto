import SwiftUI
import CallKit
import UserNotifications

struct ActivityItem: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    let summary: String
}

@MainActor final class AppState: ObservableObject {
    @Published private(set) var activities: [ActivityItem] = []
    @Published private(set) var activityUnavailable = false
    @Published private(set) var calls: [CallEntry] = []
    @Published private(set) var previousCallList: [CallEntry]?
    private var callRevision = UUID()
    @Published private(set) var callsUnavailable = false
    @Published var callStatus = CheckStatus.pending("Checking…")
    @Published private(set) var callFilterEnabled: Bool?
    @Published var notice = ""
    @Published private(set) var dontSave: Bool
    @Published private(set) var cadence: Int
    @Published private(set) var schedulingReview = false
    private let activityURL: URL
    static let extensionID = (Bundle.main.bundleIdentifier ?? "com.example.privacyguard") + ".CallDirectory"

    init() {
        dontSave = UserDefaults.standard.object(forKey: "dontSave") as? Bool ?? true
        cadence = UserDefaults.standard.object(forKey: "cadence") as? Int ?? 7
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? excluded.setResourceValues(values)
        activityURL = directory.appendingPathComponent("activity.json")
        reloadLocalData()
    }

    func reloadLocalData() {
        do {
            if dontSave {
                try removeActivityFile()
                activities = []
            } else {
                activities = try JSONDecoder().decode([ActivityItem].self, from: Data(contentsOf: activityURL))
            }
            activityUnavailable = false
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            activities = []
            activityUnavailable = false
        } catch {
            activityUnavailable = true
        }
        do {
            let loaded = try CallStore.read()
            if loaded != calls { previousCallList = nil }
            calls = loaded
            callsUnavailable = false
        } catch {
            callsUnavailable = true
        }
    }

    private func removeActivityFile() throws {
        do { try FileManager.default.removeItem(at: activityURL) }
        catch let error as CocoaError where error.code == .fileNoSuchFile { return }
    }

    func setDontSave(_ disabled: Bool) {
        guard disabled != dontSave else { return }
        if disabled {
            dontSave = true
            UserDefaults.standard.set(true, forKey: "dontSave")
            activities = []
        }
        do {
            try removeActivityFile()
            activityUnavailable = false
            if !disabled {
                dontSave = false
                UserDefaults.standard.set(false, forKey: "dontSave")
            }
        } catch {
            activityUnavailable = true
            notice = "Activity saving is off. Couldn’t remove the previous history. Unlock your device and retry in Activity."
        }
    }

    func record(_ summary: String) {
        guard !dontSave else { return }
        guard !activityUnavailable else {
            notice = "History is unavailable. This check was not saved."
            return
        }
        let updated = [ActivityItem(summary: summary)] + Array(activities.prefix(99))
        do {
            try JSONEncoder().encode(updated).write(to: activityURL, options: [.atomic, .completeFileProtection])
            activities = updated
        } catch { notice = "Could not update local activity: \(error.localizedDescription)" }
    }

    func clear() {
        do {
            try removeActivityFile()
            activities = []
            activityUnavailable = false
        } catch { notice = "Could not delete local activity: \(error.localizedDescription)" }
    }
    func refreshCalls() {
        CXCallDirectoryManager.sharedInstance.getEnabledStatusForExtension(withIdentifier: Self.extensionID) { status, error in
            Task { @MainActor in
                self.callFilterEnabled = error == nil && status != .unknown ? status == .enabled : nil
                switch self.callFilterEnabled {
                case true: self.callStatus = .verified("Enabled · verified")
                case false: self.callStatus = .attention("Call Protection is off")
                default: self.callStatus = .unverified("Not verified")
                }
            }
        }
    }
    func undoCallChange() {
        guard let previousCallList else { return }
        if saveCalls(previousCallList) { self.previousCallList = nil }
    }

    @discardableResult func saveCalls(_ entries: [CallEntry]) -> Bool {
        guard !callsUnavailable else { return false }
        do {
            let ordered = entries.sorted { $0.number < $1.number }
            guard ordered != calls else { return true }
            try CallStore.write(ordered)
            previousCallList = calls
            calls = ordered
            let revision = UUID()
            callRevision = revision
            CXCallDirectoryManager.sharedInstance.reloadExtension(withIdentifier: Self.extensionID) { error in
                Task { @MainActor in
                    guard self.callRevision == revision else { return }
                    if let error { self.notice = "Saved locally. iOS could not reload the list: \(error.localizedDescription)" }
                    self.refreshCalls()
                }
            }
            return true
        } catch { notice = "Call list not saved: \(error.localizedDescription)"; return false }
    }
    func scheduleReview(every days: Int, announce: Bool = true) async {
        guard !schedulingReview, [0, 1, 7, 30].contains(days) else { return }
        schedulingReview = true
        defer { schedulingReview = false }
        let center = UNUserNotificationCenter.current()
        do {
            if days == 0 {
                center.removePendingNotificationRequests(withIdentifiers: [ReviewNotificationDelegate.reminderID])
                if announce { notice = "Review reminders off" }
            } else {
                guard try await center.requestAuthorization(options: [.alert, .sound]) else { notice = "Allow notifications in Settings to receive reminders."; return }
                let content = UNMutableNotificationContent()
                content.title = "Protection Review"
                content.body = "Review your screen lock, call filtering, and browser privacy."
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(days) * 86400, repeats: true)
                try await center.add(.init(identifier: ReviewNotificationDelegate.reminderID, content: content, trigger: trigger))
                notice = days == 1 ? "Daily review scheduled" : "Review scheduled every \(days) days"
            }
            cadence = days
            UserDefaults.standard.set(days, forKey: "cadence")
        } catch { notice = "Reminder failed: \(error.localizedDescription)" }
    }
}
