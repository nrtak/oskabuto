import SwiftUI

@main struct PrivacyGuardApp: App {
    @StateObject private var state = AppState()
    var body: some Scene { WindowGroup { RootView().environmentObject(state) } }
}
