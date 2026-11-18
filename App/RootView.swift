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
    @State private var editingEntry: CallEntry?
    var body: some View {
        Form {
            Section("Call directory") {
                StatusLabel(status: state.callStatus)
                Button("Open call blocking settings") {
                    Task {
                        do { try await CXCallDirectoryManager.sharedInstance.openSettings() }
                        catch { state.notice = "Open Settings and search for Call Blocking & Identification." }
                    }
                }
                Button("Refresh status") { state.refreshCalls() }
                DisclosureGroup("Check in Settings") {
                    SettingsSteps(steps: ["Open Phone settings.", "Tap Call Blocking & Identification.", "Turn on Kabuto."])
                }
            }
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
                ForEach(state.calls) { entry in
                    Button {
                        editingEntry = entry
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(verbatim: "+\(entry.number)")
                                Text(entry.blocked ? "Block" : "Label only · \(entry.label)").font(.caption)
                            }
                            Spacer()
                            Image(systemName: "pencil").accessibilityHidden(true)
                        }
                    }
                }
                    .onDelete { offsets in var entries = state.calls; entries.remove(atOffsets: offsets); state.saveCalls(entries) }
            } }
            if state.previousCallList != nil && !state.callsUnavailable {
                Button("Undo last change", systemImage: "arrow.uturn.backward") { state.undoCallChange() }
            }
            Text("Call Protection uses the numbers you add here. Live Caller ID and reputation lookups are unavailable.").font(.caption)
        }.navigationTitle("Call Protection")
        .sheet(item: $editingEntry) { entry in
            EditCallRule(entry: entry) { changed in
                guard !state.callsUnavailable, state.calls.contains(entry) else { return false }
                return state.saveCalls(state.calls.filter { $0.number != changed.number } + [changed])
            }
        }
    }
}

private struct EditCallRule: View {
    let entry: CallEntry
    let save: (CallEntry) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var blocked: Bool
    @State private var label: String
    @State private var saveFailed = false

    init(entry: CallEntry, save: @escaping (CallEntry) -> Bool) {
        self.entry = entry
        self.save = save
        _blocked = State(initialValue: entry.blocked)
        _label = State(initialValue: entry.label)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("When this number calls", selection: $blocked) {
                        Text("Label only").tag(false)
                        Text("Block").tag(true)
                    }.pickerStyle(.segmented)
                    if !blocked { TextField("Caller label", text: $label) }
                    if saveFailed { Text("Couldn’t update this rule. Reopen it and try again.").font(.footnote) }
                } header: { Text(verbatim: "+\(entry.number)") }
            }
            .navigationTitle("Edit call rule").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let name = String(label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
                        if save(.init(number: entry.number, label: name, blocked: blocked)) { dismiss() }
                        else { saveFailed = true }
                    }.disabled(!blocked && label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct MessageDemoView: View {
    var body: some View {
        Form {
            StatusLabel(status: .unverified("Message filter not verified"))
            DisclosureGroup("Check in Settings") {
                SettingsSteps(steps: ["Open Messages settings.", "Find the settings for unknown senders or text message filtering.", "Select Kabuto as the SMS filter."])
            }
            NavigationLink("Check a message") { MessageCheckView() }
            Text("Applies to eligible SMS and MMS from unknown senders. Filtering runs on your device.").font(.footnote)
        }.navigationTitle("Message Filter")
    }
}

struct TextSafetyView: View {
    private enum Mode: Hashable { case link, message }
    @State private var mode = Mode.link
    var body: some View {
        VStack(spacing: 0) {
            Picker("What to check", selection: $mode) {
                Text("Link").tag(Mode.link)
                Text("Message").tag(Mode.message)
            }.pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 8)
            switch mode {
            case .link: CheckerView()
            case .message: MessageCheckView()
            }
        }
    }
}

struct MessageCheckView: View {
    @State private var text = ""
    @State private var checkedText: String?
    @FocusState private var editing: Bool
    var body: some View {
        Form {
            Section("Message text") {
                TextField("Paste or type a message", text: $text, axis: .vertical)
                    .lineLimit(2...8).focused($editing).accessibilityIdentifier("messageInput")
                PasteButton(payloadType: String.self) { items in if let first = items.first { text = first } }
                Button("Check message") { editing = false; checkedText = text }
                    .modifier(KabutoPrimaryAction())
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if checkedText == text { MessageResultSection(result: SafetyEngine.checkMessage(text)) }
            Text("Message checks run on this device. The message and its result stay out of Activity.").font(.footnote)
        }
        .navigationTitle("Check a message").navigationBarTitleDisplayMode(.inline)
        .onChange(of: text) { _, _ in checkedText = nil }
    }
}

struct CheckerView: View {
    @EnvironmentObject var state: AppState
    var qrMode = false
    @State private var input = ""
    @State private var checked: (input: String, result: SafetyResult)?
    @State private var scanning = false
    @State private var photoSession = UUID()
    @FocusState private var editing: Bool

    var body: some View {
        Form {
            Section(qrMode ? "QR contents" : "Link to check") {
                if qrMode {
                    Button("Scan with camera", systemImage: "camera") {
                        photoSession = UUID()
                        scanning = true
                    }
                    QRPhotoPicker(onStart: { editing = false; checked = nil }) { value in
                        input = value
                        check(value)
                    }
                    .id(photoSession)
                }
                TextField(qrMode ? "Enter QR contents" : "Enter a web address",
                          text: $input, axis: .vertical)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().focused($editing)
                    .accessibilityIdentifier("checkerInput")
                PasteButton(payloadType: String.self) { values in
                    if let first = values.first { input = first }
                }
                Button("Check locally") {
                    if qrMode { photoSession = UUID() }
                    check(input)
                }
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
            if qrMode { photoSession = UUID() }
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
                    Task {
                        await state.scheduleReview(every: days)
                        selectedDays = nil
                    }
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
                check("Cross-site tracking", ["Open Safari settings.", "Review Prevent Cross-Site Tracking."])
                check("Website warnings", ["Open Safari settings.", "Review Fraudulent Website Warning."])
                check("Other browsers", ["Open your browser’s privacy settings.", "Review tracking protection and safe browsing."])
            } header: {
                Label("Browsing", systemImage: "safari")
            }
            Section {
                check("App permissions", ["Open Privacy & Security in Settings.", "Choose Camera, Microphone, or Photos.", "Review which apps have access."])
                check("Location access", ["Open Privacy & Security in Settings.", "Tap Location Services.", "Review access for each app."])
                check("App tracking", ["Open Privacy & Security in Settings.", "Tap Tracking.", "Review which apps can request tracking."])
                check("Configuration profiles", ["Open General in Settings.", "Tap VPN & Device Management.", "Review any installed profiles."])
            } header: {
                Label("Apps & device", systemImage: "iphone")
            } footer: {
                Text("Guided checks. You mark what you’ve reviewed for this visit.")
            }
        }
        .navigationTitle("Privacy Checks").navigationBarTitleDisplayMode(.inline)
    }

    private func check(_ title: String, _ steps: [String]) -> some View {
        let isReviewed = reviewed.contains(title)
        return DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                StatusLabel(status: .unverified("Setting not verified")).font(.subheadline)
                SettingsSteps(steps: steps).font(.subheadline)
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
