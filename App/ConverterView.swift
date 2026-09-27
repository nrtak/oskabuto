import SwiftUI

private enum PickerSide: String, Identifiable { case source, target; var id: String { rawValue } }

struct ConverterView: View {
    @ObservedObject var store: ConverterStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var picker: PickerSide?
    @State private var showsAbout = false
    @StateObject private var saved = SavedConversions()
    @State private var draft: SavedConversion?
    @State private var showsSaved = false
    @FocusState private var editing: Bool

    private var blue: Color { Color(uiColor: .secondarySystemBackground) }
    private var yellow: Color { Color(uiColor: .secondarySystemBackground) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("From").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        currencyButton(store.source, side: .source)
                        TextField("Amount", text: $store.amount)
                            .font(.system(size: 44, weight: .medium))
                            .keyboardType(.decimalPad).focused($editing)
                            .accessibilityLabel("Amount to convert")
                    }.padding(22).background(yellow, in: RoundedRectangle(cornerRadius: 24))

                    HStack { Spacer(); Button { editing = false; store.swap() } label: {
                        Image(systemName: "arrow.up.arrow.down").font(.title3.weight(.semibold))
                            .frame(width: 48, height: 48).background(Color.blue, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.white)
                    }.accessibilityLabel("Swap currencies"); Spacer() }.padding(.vertical, -12)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("To").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        currencyButton(store.target, side: .target)
                        Text(store.result).font(.system(size: 44, weight: .medium))
                            .monospacedDigit().minimumScaleFactor(0.4).lineLimit(1)
                            .accessibilityLabel("Converted amount: \(store.result) \(store.target)")
                            .textSelection(.enabled)
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 24))
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color(uiColor: .separator).opacity(0.4), lineWidth: 1))

                    VStack(spacing: 7) {
                        Text(store.detail)
                        if let checked = store.lastChecked { Text(checked).font(.caption2) }
                        if store.updateFailed {
                            Label(store.snapshot == nil ? "Couldn’t load rates. Try again when connected." : "Couldn’t refresh. Showing saved rates.", systemImage: "wifi.slash")
                        }
                        if store.cacheWriteFailed { Text("Rates loaded, but couldn’t save for offline use.") }
                        Button { Task { await store.refresh(force: true) } } label: {
                            HStack { if store.isLoading { ProgressView() }; Text(store.isLoading ? "Refreshing…" : "Refresh rates") }
                        }.disabled(store.isLoading).frame(minHeight: 44)
                    }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).multilineTextAlignment(.center)

                    HStack(spacing: 12) {
                        Button { editing = false; draft = store.savedDraft() } label: {
                            Label("Save conversion", systemImage: "bookmark").frame(minHeight: 44)
                        }.buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 8))
                            .disabled(store.savedDraft() == nil || saved.loadError != nil)
                        Button { editing = false; showsSaved = true } label: {
                            Text("Saved (\(saved.items.count))").frame(minHeight: 44)
                        }.buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 8))
                    }

                    HStack {
                        Text("Favorites").font(.headline)
                        Spacer()
                        Button { editing = false; picker = .target } label: { Label("Search", systemImage: "magnifyingglass") }.frame(minHeight: 44)
                    }
                    VStack(spacing: 0) {
                        ForEach(store.favorites, id: \.self) { code in
                            Button { store.target = code; editing = false } label: {
                                HStack(spacing: 12) {
                                    Text(currencySymbol(code)).font(.title3.weight(.medium))
                                        .frame(width: 38, height: 38)
                                        .background(store.target == code ? Color.blue : blue, in: Circle())
                                        .foregroundStyle(store.target == code ? Color.white : Color.blue)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(Currency.named(code).name).font(.subheadline.weight(.medium))
                                        Text("\(code) · \(Currency.named(code).countryLabel)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    Text(store.result(for: code)).font(.subheadline.weight(.medium)).monospacedDigit()
                                }.foregroundStyle(.primary).frame(minHeight: 60).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("Convert to \(Currency.named(code).name)")
                                .accessibilityAddTraits(store.target == code ? [.isSelected] : [])
                            Divider()
                        }
                    }
                    if store.favorites.isEmpty { Text("Star currencies in Search to keep them here.").font(.caption).foregroundStyle(.secondary) }
                    Text("Reference rates by Frankfurter\nBank and card rates may differ.")
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).padding(.top, 14)
                }.padding(20)
            }
            .navigationTitle("Simple Currency")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button { showsAbout = true } label: { Image(systemName: "info.circle") }.accessibilityLabel("About rates and privacy") }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editing = false } }
            }
            .sheet(item: $picker) { side in CurrencyPicker(store: store, title: side == .target ? "Search currency" : "Convert from", select: { code in
                if side == .source { store.source = code } else { store.target = code }; picker = nil
            }) }
            .sheet(isPresented: $showsAbout) { about }
            .sheet(item: $draft) { entry in SaveConversionView(draft: entry, saved: saved) }
            .sheet(isPresented: $showsSaved) { SavedConversionsView(saved: saved) }
            .task { await store.refresh() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.refresh() } } }
        }
    }

    private func currencyButton(_ code: String, side: PickerSide) -> some View {
        Button { editing = false; picker = side } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(code).font(.headline)
                        Text("Click to change").font(.caption).foregroundStyle(.blue)
                    }
                    Text(Currency.named(code).name).font(.subheadline).foregroundStyle(.secondary)
                    Text(Currency.named(code).countryLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }.foregroundStyle(.primary).frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("\(side == .source ? "From" : "To"): \(Currency.named(code).name), \(Currency.named(code).countryLabel). Change currency")
    }

    private func currencySymbol(_ code: String) -> String {
        ["USD": "$", "CAD": "$", "EUR": "€", "GBP": "£", "JPY": "¥", "CNY": "¥", "KRW": "₩", "INR": "₹"][code] ?? String(code.prefix(1))
    }

    private var about: some View {
        NavigationStack {
            List {
                Section("Exchange rates") {
                    Text("Daily reference rates from Frankfurter. These are estimates, not guaranteed transaction prices. Different currencies can have different rate dates; both dates appear when needed. Last checked shows when this device last downloaded rates, in your local time zone. The provider supplies a rate date, not an exact publication time.")
                    Link("Frankfurter and data sources", destination: URL(string: "https://frankfurter.dev/")!)
                    Link("Provider terms", destination: URL(string: "https://frankfurter.dev/license/")!)
                }
                Section("Offline use") { Text("After a successful update, rates are saved on this iPhone. Refresh requires internet. Older rates stay clearly dated.") }
                Section("Privacy") { Text("No account, ads, or analytics. Your amount, favorites, saved conversions, notes and attached photos are stored locally and may be included in your device backups. The app does not upload notes or photos. Camera access is used only when you choose Take photo; Photos lets you select an individual image. The app requests a USD rate table over HTTPS; it does not send your entered amount. The rate service and network infrastructure process the request.") }
                Section("Currency search") { Text("This first version includes 26 currencies. Search by country, currency name or code. Croatia uses EUR; Tahiti and Bora Bora use XPF.") }
            }.navigationTitle("About").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsAbout = false } } }
        }
    }
}

private struct CurrencyPicker: View {
    @ObservedObject var store: ConverterStore
    let title: String
    let select: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var results: [Currency] {
        Currency.all.filter { $0.matches(query) }.sorted {
            let a = store.favorites.contains($0.code), b = store.favorites.contains($1.code)
            return a == b ? $0.name < $1.name : a
        }
    }
    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { currency in
                    HStack {
                        Button { select(currency.code) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(currency.code).font(.headline)
                                Text(currency.name).font(.subheadline).foregroundStyle(.secondary)
                                Text(currency.countryLabel(matching: query)).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Button { store.toggleFavorite(currency.code) } label: {
                            Image(systemName: store.favorites.contains(currency.code) ? "star.fill" : "star")
                                .frame(width: 44, height: 44)
                        }.buttonStyle(.borderless).accessibilityLabel("\(store.favorites.contains(currency.code) ? "Remove" : "Favorite") \(currency.name)")
                    }
                }
                if results.isEmpty { Text("No supported currency found.").foregroundStyle(.secondary) }
            }.searchable(text: $query, prompt: "Country, currency or code")
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
