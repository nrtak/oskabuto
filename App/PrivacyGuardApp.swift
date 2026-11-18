import SwiftUI
import UserNotifications

@main struct PrivacyGuardApp: App {
    @UIApplicationDelegateAdaptor(ReviewNotificationDelegate.self) private var notifications
    @StateObject private var state = AppState()
    var body: some Scene { WindowGroup { RootView().environmentObject(state) } }
}

final class ReviewNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {
    nonisolated static let reminderID = "protection-review"
    @Published var reviewRequested = false

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    private nonisolated static func opensReview(_ response: UNNotificationResponse) -> Bool {
        response.notification.request.identifier == reminderID && response.actionIdentifier == UNNotificationDefaultActionIdentifier
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard Self.opensReview(response) else { return }
        await MainActor.run { self.reviewRequested = true }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        notification.request.identifier == Self.reminderID ? [.banner, .list, .sound] : []
    }
}
