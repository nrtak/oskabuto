import SwiftUI
import CallKit

struct RootView: View {
    private enum Tab: Hashable { case home, protection, activity, settings }
    @EnvironmentObject var state: AppState
    @EnvironmentObject private var notifications: ReviewNotificationDelegate
    @State private var selectedTab = Tab.home
    @State private var protectionPath: [ProtectionRoute] = []
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("welcomed") private var welcomed = false
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { HomeView() }.tabItem { Label("Home", systemImage: "house") }.tag(Tab.home)
            NavigationStack(path: $protectionPath) {
                ProtectionView().navigationDestination(for: ProtectionRoute.self) { $0.destination }
            }.tabItem { Label("Protection", systemImage: "shield") }.tag(Tab.protection)
            NavigationStack { ActivityView() }.tabItem { Label("Activity", systemImage: "clock") }.tag(Tab.activity)
            NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "gearshape") }.tag(Tab.settings)
        }.tint(.blue)
        .task { state.refreshCalls() }
        .onChange(of: notifications.reviewRequested && welcomed, initial: true) { _, ready in
            guard ready else { return }
            selectedTab = .protection
            protectionPath = [.review]
            notifications.reviewRequested = false
        }
        .sheet(isPresented: Binding(get: { !welcomed }, set: { if !$0 { welcomed = true } })) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 24) {
                        Image("AppMark").resizable().scaledToFit().frame(width: 96, height: 96).clipShape(RoundedRectangle(cornerRadius: 22)).accessibilityHidden(true)
                        Text("A quieter, more private phone").font(.largeTitle.bold()).multilineTextAlignment(.center)
                        Text("Your checks stay on your device. Activity saving starts off. Call and message protection need your approval in Settings.")
                        Text("You can get a weekly Protection Review reminder and change it anytime in Settings.").font(.callout)
                        Button("Continue & enable weekly review") {
                            welcomed = true
                            Task { await state.scheduleReview(every: 7) }
                        }.modifier(KabutoPrimaryAction())
                        Button("Continue without notifications") {
                            welcomed = true
                            Task { await state.scheduleReview(every: 0, announce: false) }
                        }
                    }.padding(28)
                }
            }.interactiveDismissDisabled()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                state.reloadLocalData()
                state.refreshCalls()
            }
        }
        .alert("Kabuto", isPresented: Binding(get: { !state.notice.isEmpty }, set: { if !$0 { state.notice = "" } })) { Button("OK") { state.notice = "" } } message: { Text(state.notice) }
    }
}

struct CallsView: View {
    @EnvironmentObject var state: AppState
    @State private var number = ""
    @State private var label = ""
    @State private var blocked = false
    var body: some View {
        Form {
            Section("Call directory") {
                Text(state.callStatus)
                Button("Open call blocking settings") {
                    Task {
                        do { try await CXCallDirectoryManager.sharedInstance.openSettings() }
                        catch { state.notice = "Open Settings and search for Call Blocking & Identification." }
                    }
                }
                Button("Refresh status") { state.refreshCalls() }
                Text("Enable Kabuto in Settings → Apps → Phone → Call Blocking & Identification. The app cannot read incoming calls or call history.") }
            Section("Add a number") {
                TextField("Country code + number (e.g. +14155550123)", text: $number).keyboardType(.phonePad)
                TextField("Caller label", text: $label)
                Toggle("Block this number", isOn: $blocked)
                Button("Save & reload") {
                    let text = number.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard text.range(of: #"^\+[1-9][0-9]{6,14}$"#, options: .regularExpression) != nil,
                          let value = Int64(text.dropFirst()) else { state.notice = "Enter a full international number beginning with +."; return }
                    let name = String(label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
                    guard blocked || !name.isEmpty else { state.notice = "Enter a caller label for identification."; return }
                    if state.saveCalls(state.calls.filter { $0.number != value } + [.init(number: value, label: name, blocked: blocked)]) {
                        number = ""; label = ""; blocked = false
                    }
                }
            }.disabled(state.callsUnavailable)
            if state.callsUnavailable {
                Section("Your numbers") {
                    Text("Your saved numbers could not be read. Unlock your device and try again.")
                    Button("Retry loading numbers") { state.reloadLocalData() }
                }
            } else if !state.calls.isEmpty { Section("Your numbers") {
                ForEach(state.calls) { entry in VStack(alignment: .leading) { Text("+\(entry.number)"); Text(entry.blocked ? "On your block list" : entry.label).font(.caption) } }
                    .onDelete { offsets in var entries = state.calls; entries.remove(atOffsets: offsets); state.saveCalls(entries) }
            } }
            Text("Call Protection uses the numbers you add here. Live Caller ID and reputation lookups are unavailable.").font(.caption)
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
                if !result.isEmpty { Text(result) }
            }
            Text("Conservative prototype rules can miss scams or flag legitimate messages. Message contents and senders are never saved or sent to a server.")
        }.navigationTitle("Message Filter")
        .onChange(of: text) { _, _ in result = "" }
    }
}

struct CheckerView: View {
    @EnvironmentObject var state: AppState
    var qrMode = false
    @State private var input = ""
    @State private var checked: (input: String, result: SafetyResult)?
    @State private var scanning = false
    @FocusState private var editing: Bool

    var body: some View {
        Form {
            Section(qrMode ? "QR contents" : "Link to check") {
                if qrMode { Button("Scan with camera", systemImage: "camera") { scanning = true } }
                TextField(qrMode ? "Enter QR contents" : "Enter a web address",
                          text: $input, axis: .vertical)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().focused($editing)
                    .accessibilityIdentifier("checkerInput")
                PasteButton(payloadType: String.self) { values in
                    if let first = values.first { input = first }
                }
                Button("Check locally") { check(input) }
                    .modifier(KabutoPrimaryAction())
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let checked, checked.input == input {
                CheckResultSection(result: checked.result, qrContents: qrMode ? checked.input : nil)
            }
            Section {
                Text("Kabuto checks the text on this device. Your links and QR contents stay out of Activity.")
                if !qrMode {
                    Text("From another app, tap Share and choose Check with Kabuto.")
                }
            }.font(.footnote).foregroundStyle(.secondary)
        }
        .onChange(of: input) { _, newValue in
            if let checked, checked.input != newValue { self.checked = nil }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(qrMode ? "QR Safety Scanner" : "Link Checker")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $scanning) {
            QRScanner { value in
                input = value
                scanning = false
                check(value)
            }
        }
    }

    private func check(_ input: String) {
        editing = false
        let value = SafetyEngine.check(input)
        checked = (input, value)
        state.record("\(qrMode ? "QR" : "Link") check: \(value.title)")
    }
}

struct ActivityView: View {
    @State private var confirmDelete = false
    @EnvironmentObject var state: AppState
    var body: some View {
        Group {
            if state.activityUnavailable {
                ContentUnavailableView {
                    Label("History unavailable", systemImage: "clock")
                } description: {
                    Text(state.dontSave ? "Saving is off. Unlock your device and retry removing previous history." : "Your saved history could not be read. Unlock your device and try again.")
                } actions: {
                    Button("Retry") { state.reloadLocalData() }
                    if !state.dontSave {
                        Button("Delete saved history", role: .destructive) { confirmDelete = true }
                    }
                }
            } else if state.activities.isEmpty {
                ContentUnavailableView {
                    Label(state.dontSave ? "Activity saving is off" : "No checks saved yet",
                          systemImage: state.dontSave ? "eye.slash" : "clock")
                } description: {
                    Text(state.dontSave ? "To keep a local history, turn off Don’t Save Activity in Settings." : "Results from Link Checker and QR Safety Scanner will appear here.")
                }
            } else {
                List {
                    Section {
                        ForEach(state.activities) { item in
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.summary)
                                    Text(item.date, format: .dateTime.month().day().hour().minute())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: item.summary.hasPrefix("QR") ? "qrcode.viewfinder" : "link")
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(item.summary)
                            .accessibilityValue(Text(item.date, format: .dateTime.month().day().hour().minute()))
                            .accessibilityIdentifier("activitySummary")
                        }
                    } header: { Text("Recent checks") } footer: { Text("Only result summaries are saved on this device.") }
                    Button("Delete all activity", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle("Activity").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete all saved checks?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete all activity", role: .destructive) { state.clear() }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedDays: Int?
    var body: some View {
        Form {
            Section("Activity history") {
                Toggle("Don't Save Activity", isOn: Binding(get: { state.dontSave }, set: state.setDontSave))
                Text("Turning this on deletes existing activity. Call list and preferences remain so protection still works.").font(.caption)
            }
            Section("Protection Review") {
                Picker("Remind me", selection: Binding(get: { selectedDays ?? state.cadence }, set: { selectedDays = $0 })) {
                    Text("Off").tag(0); Text("Daily").tag(1); Text("Weekly").tag(7); Text("Every 30 days").tag(30)
                }.pickerStyle(.menu)
                Button((selectedDays ?? state.cadence) == 0 ? "Turn off reminder" : "Set reminder") {
                    let days = selectedDays ?? state.cadence
                    Task { await state.scheduleReview(every: days) }
                }.modifier(KabutoPrimaryAction())
                Text("Tap to apply your choice. Delivery depends on your notification settings.").font(.caption)
            }.disabled(state.schedulingReview)
            Section { Text("No accounts, ads, analytics, breach searches, reverse lookup, or cloud history.") }
        }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
        .onDisappear { selectedDays = nil }
    }
}

struct PrivacyChecksView: View {
    @State private var reviewed: Set<String> = []
    var body: some View {
        List {
            Section {
                check("Cross-site tracking", "Find Safari in Settings. Review Prevent Cross-Site Tracking.")
                check("Website warnings", "In Safari settings, look for Fraudulent Website Warning.")
                check("Other browsers", "Open your browser’s privacy settings. Review tracking protection and safe browsing.")
            } header: {
                Label("Browsing", systemImage: "safari")
            }
            Section {
                check("App permissions", "In Settings → Privacy & Security, check which apps can use your camera, microphone, and photos.")
                check("Location access", "Open Settings → Privacy & Security → Location Services. Review access for each app.")
                check("App tracking", "Open Settings → Privacy & Security → Tracking. Review which apps can request tracking.")
                check("Configuration profiles", "In Settings → General → VPN & Device Management, review any installed profiles.")
            } header: {
                Label("Apps & device", systemImage: "iphone")
            } footer: {
                Text("Guided checks. You mark what you’ve reviewed for this visit.")
            }
        }
        .navigationTitle("Privacy Checks").navigationBarTitleDisplayMode(.inline)
    }

    private func check(_ title: String, _ instruction: String) -> some View {
        let isReviewed = reviewed.contains(title)
        return DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text(instruction).font(.subheadline).foregroundStyle(.secondary)
                Button(isReviewed ? "Undo review" : "Mark as reviewed") {
                    if isReviewed { reviewed.remove(title) } else { reviewed.insert(title) }
                }
                .modifier(KabutoPrimaryAction())
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isReviewed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isReviewed ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                Text(title).foregroundStyle(.primary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(isReviewed ? "Reviewed by you" : "To review")
        }
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
