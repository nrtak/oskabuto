import SwiftUI

private enum PickerSide: String, Identifiable { case source, target; var id: String { rawValue } }

struct ConverterView: View {
    @ObservedObject var store: ConverterStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var picker: PickerSide?
    @State private var showsAbout = false
    @StateObject private var saved = SavedConversions()
    @State private var draft: SavedConversion?
    @State private var showsSaved = false
    @FocusState private var editing: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(spacing: 10) {
                            amountCard(source: true)
                            amountCard(source: false)
                        }.id("amounts")

                        if !editing {
                            rateDetails
                            saveButtons
                            favorites
                            Text("Reference rates by Frankfurter · Bank and card rates may differ.")
                                .font(.caption2).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                        }
                    }.padding(.horizontal, 16).padding(.vertical, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: editing) { _, active in
                    if active { proxy.scrollTo("amounts", anchor: .top) }
                }
            }
            .navigationTitle("Convert Currency")
            .navigationBarTitleDisplayMode(.inline)
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

    private func amountCard(source: Bool) -> some View {
        let code = source ? store.source : store.target
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                currencyButton(code, side: source ? .source : .target)
                if source {
                    Button { store.swap() } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.headline).frame(width: 44, height: 44)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.white)
                    }.accessibilityLabel("Swap currencies")
                }
            }
            if !source {
                Rectangle().fill(Color.blue.opacity(0.35)).frame(height: 1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Currency.named(code).symbol)
                    .font(.title2.weight(.medium)).foregroundStyle(.secondary)
                    .fixedSize().accessibilityHidden(true)
                if source {
                    TextField("Amount", text: $store.amount)
                        .font(.system(size: 36, weight: .medium)).monospacedDigit()
                        .keyboardType(.decimalPad).focused($editing)
                        .accessibilityLabel("Amount to convert in \(Currency.named(code).name)")
                } else {
                    Text(store.result).font(.system(size: 36, weight: .semibold))
                        .monospacedDigit().minimumScaleFactor(0.4).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Converted amount: \(store.result) \(code)")
                        .textSelection(.enabled)
                }
            }
        }
        .padding(14)
        .background(source ? Color(uiColor: .secondarySystemBackground) : Color.blue.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(source ? Color.clear : Color.blue.opacity(0.55), lineWidth: 1.5))
    }

    private var rateDetails: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.detail)
                if let checked = store.lastChecked { Text(checked) }
                if store.updateFailed {
                    Label(store.snapshot == nil ? "Couldn’t load rates. Try again when connected." : "Couldn’t refresh. Showing saved rates.", systemImage: "wifi.slash")
                }
                if store.cacheWriteFailed { Text("Rates loaded, but couldn’t save for offline use.") }
            }.font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button { Task { await store.refresh(force: true) } } label: {
                Group {
                    if store.isLoading { ProgressView() }
                    else { Image(systemName: "arrow.clockwise") }
                }.frame(width: 44, height: 44)
            }.disabled(store.isLoading).accessibilityLabel("Refresh rates")
        }
    }

    private var saveButtons: some View {
        HStack(spacing: 10) {
            Button { draft = store.savedDraft() } label: {
                Label("Save conversion", systemImage: "bookmark")
                    .frame(maxWidth: .infinity, minHeight: 32)
            }.buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 8))
                .disabled(store.savedDraft() == nil || saved.loadError != nil)
            Button { showsSaved = true } label: {
                Text("Saved (\(saved.items.count))").frame(minHeight: 32)
            }.buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 8))
        }.font(.subheadline)
    }

    private var favorites: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Favorites").font(.subheadline.weight(.semibold))
                Spacer()
                Button { picker = .target } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }.font(.subheadline).frame(minHeight: 44)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.favorites, id: \.self) { code in
                        Button { store.target = code } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(code).font(.subheadline.weight(.semibold))
                                Text(Currency.named(code).countryLabel).font(.caption2)
                                    .foregroundStyle(.secondary).lineLimit(1)
                                Text("\(Currency.named(code).symbol) \(store.result(for: code))")
                                    .font(.subheadline.weight(.medium)).monospacedDigit()
                                    .lineLimit(1).minimumScaleFactor(0.5)
                            }.frame(width: 132, alignment: .leading).padding(10)
                                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(store.target == code ? Color.blue : Color.clear, lineWidth: 1.5))
                        }.buttonStyle(.plain)
                            .accessibilityLabel("Convert to \(Currency.named(code).name), \(store.result(for: code)) \(code)")
                            .accessibilityAddTraits(store.target == code ? [.isSelected] : [])
                    }
                }.padding(2)
            }
            if store.favorites.isEmpty {
                Text("Star currencies in Search to keep them here.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func currencyButton(_ code: String, side: PickerSide) -> some View {
        Button { editing = false; picker = side } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(side == .source ? "From" : "To").font(.caption).foregroundStyle(.secondary)
                    Text(code).font(.headline)
                    Text("Click to change").font(.caption).foregroundStyle(.blue)
                }
                if !editing {
                    Text(Currency.named(code).name).font(.caption).foregroundStyle(.secondary)
                }
                Text(Currency.named(code).countryLabel).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(editing ? 1 : 2)
            }.foregroundStyle(.primary).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("\(side == .source ? "From" : "To"): \(Currency.named(code).name), \(Currency.named(code).countryLabel). Change currency")
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
