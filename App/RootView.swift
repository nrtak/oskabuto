import SwiftUI

struct RootView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("welcomed") private var welcomed = false
    var body: some View {
        TabView {
            NavigationStack { HomeView() }.tabItem { Label("Home", systemImage: "house") }
            NavigationStack { ProtectionView() }.tabItem { Label("Protection", systemImage: "shield") }
            NavigationStack { ActivityView() }.tabItem { Label("Activity", systemImage: "clock") }
            NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "gearshape") }
        }.tint(.blue)
        .task { state.refreshCalls() }
        .sheet(isPresented: Binding(get: { !welcomed }, set: { if !$0 { welcomed = true } })) {
            NavigationStack {
                VStack(spacing: 24) {
                    Image("AppMark").resizable().scaledToFit().frame(width: 96, height: 96).clipShape(RoundedRectangle(cornerRadius: 22)).accessibilityHidden(true)
                    Text("A quieter, more private phone").font(.largeTitle.bold()).multilineTextAlignment(.center)
                    Text("Your checks stay on your device. Activity saving starts off. Call and message protection need your approval in Settings.")
                    Text("A weekly Protection Review is selected by default. Allow notifications to receive it; you can change the cadence anytime.").font(.callout)
                    Button("Continue & enable weekly review") { welcomed = true; Task { await state.scheduleReview() } }.modifier(KabutoPrimaryAction())
                    Button("Continue without notifications") { welcomed = true }
                }.padding(28)
            }.interactiveDismissDisabled()
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { state.refreshCalls() } }
        .alert("Kabuto", isPresented: Binding(get: { !state.notice.isEmpty }, set: { if !$0 { state.notice = "" } })) { Button("OK") { state.notice = "" } } message: { Text(state.notice) }
    }
}

struct ProtectionView: View {
    var body: some View {
        List {
            NavigationLink("Set up Kabuto") { SetupView() }
            NavigationLink("Call Protection") { CallsView() }
            NavigationLink("SMS / MMS filter") { MessageDemoView() }
            NavigationLink("Secure DNS") { DNSView() }
            NavigationLink("Browser & device privacy") { PrivacyChecksView() }
            Section("Future integration") {
                Text("Live Caller ID: unavailable in this MVP. Requires Apple capability approval and a compatible private lookup service. No live or reputation lookup is performed.")
            }
        }.navigationTitle("Protection").navigationBarTitleDisplayMode(.inline)
    }
}

struct CallsView: View {
    @EnvironmentObject var state: AppState
    @State private var number = ""
    @State private var label = ""
    @State private var blocked = false
    var body: some View {
        Form {
            Section("Status") { Text(state.callStatus); Button("Refresh status") { state.refreshCalls() }
                Text("Enable Kabuto in Settings → Apps → Phone → Call Blocking & Identification. The app cannot read incoming calls or call history.") }
            Section("Local call list") {
                TextField("Country code + number (e.g. +14155550123)", text: $number).keyboardType(.phonePad)
                TextField("Caller label", text: $label)
                Toggle("Block this number", isOn: $blocked)
                Button("Save & reload") {
                    let text = number.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard text.range(of: #"^\+[1-9][0-9]{6,14}$"#, options: .regularExpression) != nil,
                          let value = Int64(text.dropFirst()), blocked || !label.trimmingCharacters(in: .whitespaces).isEmpty else { state.notice = "Enter a full international number beginning with + and a label for identification."; return }
                    state.saveCalls(state.calls.filter { $0.number != value } + [.init(number: value, label: String(label.prefix(80)), blocked: blocked)])
                    number = ""; label = ""
                }
                ForEach(state.calls) { entry in VStack(alignment: .leading) { Text("+\(entry.number)"); Text(entry.blocked ? "Blocked" : entry.label).font(.caption) } }
                    .onDelete { offsets in var entries = state.calls; entries.remove(atOffsets: offsets); state.saveCalls(entries) }
            }
            Text("No seeded spam list. Only your explicit entries are used. A reputation feed is a future integration.").font(.caption)
        }.navigationTitle("Call Protection")
    }
}

struct MessageDemoView: View {
    @State private var text = ""
    @State private var result = ""
    var body: some View {
        Form {
            Text("Guided status: enable Kabuto under Settings → Apps → Messages → Unknown & Spam. iOS provides no enabled-status query for this filter. It applies to eligible unknown-sender SMS/MMS, not iMessage or third-party apps.")
            Section("Try the on-device rules") {
                TextEditor(text: $text).frame(minHeight: 120)
                Button("Test classification") { result = SafetyEngine.isJunk(text) ? "Junk: urgency plus a link or sensitive/payment request." : "No filter decision: passed back to iOS. This does not prove legitimacy." }
                Text(result)
            }
            Text("Conservative prototype rules can miss scams or flag legitimate messages. Message contents and senders are never saved or sent to a server.")
        }.navigationTitle("Message Filter")
    }
}

struct CheckerView: View {
    @EnvironmentObject var state: AppState
    var qrMode = false
    @State private var input = ""
    @State private var result: SafetyResult?
    @State private var scanning = false
    var body: some View {
        Form {
            if qrMode { Button("Scan QR with camera") { scanning = true } }
            TextField(qrMode ? "QR contents or link" : "https://example.com", text: $input, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Check locally") { check() }.modifier(KabutoPrimaryAction()).disabled(input.isEmpty)
            if let result {
                Section(result.title) { ForEach(result.reasons, id: \.self) { Text($0) } }
            }
            Text("No link is opened or fetched. Only the result category can be saved in optional Activity; the link and QR contents are never saved.").font(.caption)
        }.navigationTitle(qrMode ? "QR Safety Scanner" : "Link Checker")
        .sheet(isPresented: $scanning) { QRScanner { value in input = value; scanning = false; check() } }
    }
    private func check() { let value = SafetyEngine.check(input); result = value; state.record("\(qrMode ? "QR" : "Link") check: \(value.title)") }
}

struct ActivityView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        List {
            Text(state.dontSave ? "Don't Save Activity is on. No activity is retained." : "Local tool summaries only, capped at 100. No calls, messages, URLs, or QR contents.")
            ForEach(state.activities) { item in VStack(alignment: .leading) { Text(item.summary); Text(item.date, style: .date).font(.caption) } }
            if !state.activities.isEmpty { Button("Delete all activity", role: .destructive) { state.clear() } }
        }.navigationTitle("Activity").navigationBarTitleDisplayMode(.inline)
    }
}

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Form {
            Section("Privacy") {
                Toggle("Don't Save Activity", isOn: $state.dontSave)
                Text("Turning this on deletes existing activity. Call list and preferences remain so protection still works.").font(.caption)
            }
            Section("Protection Review") {
                Picker("Cadence", selection: $state.cadence) { Text("Off").tag(0); Text("Daily").tag(1); Text("Weekly (default)").tag(7); Text("Every 30 days").tag(30) }
                Button("Enable / update reminder") { Task { await state.scheduleReview() } }.modifier(KabutoPrimaryAction())
                Text("Weekly is selected by default. Tap to allow notifications and schedule it. Delivery depends on iOS notification settings.").font(.caption)
            }
            Section { Text("No accounts, ads, analytics, breach searches, reverse lookup, or cloud history.") }
        }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyChecksView: View {
    @State private var reviewed: Set<String> = []
    private let checks = ["Safari: review Prevent Cross-Site Tracking and Fraudulent Website Warning", "Other browsers: review tracking and safe browsing in each browser", "Device: review software updates and app permissions", "Device: review Location Services and App Tracking Transparency", "Device: review installed configuration profiles"]
    var body: some View {
        List {
            Text("Guided checks. This app cannot read these settings or verify their values. Review marks are session-only self-reports.")
            ForEach(checks, id: \.self) { check in Button { if reviewed.contains(check) { reviewed.remove(check) } else { reviewed.insert(check) } } label: { Label(check + (reviewed.contains(check) ? " • Reviewed by you" : " • Not reviewed"), systemImage: reviewed.contains(check) ? "checkmark.circle" : "circle") } }
        }.navigationTitle("Privacy Checks")
    }
}

private struct KabutoPrimaryAction: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26, *), !reduceTransparency {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}
