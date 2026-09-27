import XCTest
@testable import SimpleCurrency

final class CurrencyTests: XCTestCase {
    private let snapshot = RateSnapshot(fetchedAt: Date(), rows: [
        Rate(date: "2026-09-25", base: "USD", quote: "EUR", rate: Decimal(string: "0.8")!),
        Rate(date: "2026-09-24", base: "USD", quote: "JPY", rate: 160)
    ])

    func testCrossRateAndInverse() {
        XCTAssertEqual(snapshot.multiplier(from: "EUR", to: "JPY"), 200)
        XCTAssertEqual(snapshot.multiplier(from: "EUR", to: "USD"), Decimal(string: "1.25"))
        XCTAssertEqual(snapshot.multiplier(from: "USD", to: "EUR"), Decimal(string: "0.8"))
        XCTAssertEqual(snapshot.multiplier(from: "JPY", to: "JPY"), 1)
        XCTAssertNil(snapshot.multiplier(from: "USD", to: "XPF"))
    }

    func testRateDatesPreserveBothLegs() {
        XCTAssertEqual(snapshot.dates(from: "EUR", to: "JPY"), ["2026-09-24", "2026-09-25"])
        XCTAssertEqual(snapshot.dates(from: "USD", to: "EUR"), ["2026-09-25"])
        XCTAssertNil(RateSnapshot.validDate("2026-02-30"))
    }

    func testBadRatesCannotConvert() {
        let bad = RateSnapshot(fetchedAt: Date(), rows: [
            Rate(date: "2026-09-25", base: "USD", quote: "EUR", rate: 0),
            Rate(date: "bad", base: "USD", quote: "JPY", rate: 160)
        ])
        XCTAssertNil(bad.multiplier(from: "EUR", to: "JPY"))
    }

    func testLocalizedAmountsAndInvalidInput() {
        XCTAssertEqual(Amount.parse("12,50", locale: Locale(identifier: "fr_FR")), Decimal(string: "12.5"))
        for text in ["", "-1", "1,000", "1.2.3", "$12", "NaN", "1e9"] {
            XCTAssertNil(Amount.parse(text, locale: Locale(identifier: "en_US")), text)
        }
        XCTAssertEqual(Amount.parse("0", locale: Locale(identifier: "en_US")), 0)
    }

    func testRoundingForCurrencyMinorUnits() {
        let us = Locale(identifier: "en_US")
        XCTAssertEqual(Amount.format(Decimal(string: "12.345")!, currency: .named("USD"), locale: us), "12.35")
        XCTAssertEqual(Amount.format(Decimal(string: "123.6")!, currency: .named("JPY"), locale: us), "124")
    }

    func testAllRequestedCurrenciesAndAliases() {
        let required = Set(["USD", "CAD", "MXN", "EUR", "JPY", "TWD", "KRW", "HKD", "CNY", "VND", "GBP", "AED", "QAR", "SAR", "ILS", "XPF", "FJD", "BRL"])
        XCTAssertTrue(required.isSubset(of: Set(Currency.all.map(\.code))))
        XCTAssertTrue(Currency.named("EUR").matches("Croatia"))
        XCTAssertTrue(Currency.named("XPF").matches("Bora Bora"))
        XCTAssertTrue(Currency.named("CNY").matches("RMB"))
        XCTAssertTrue(Currency.named("AED").matches("dubai"))
        XCTAssertTrue(Currency.named("EUR").matches("Germany"))
        XCTAssertTrue(Currency.named("EUR").matches("Malta"))
        XCTAssertTrue(Currency.named("EUR").matches("Bulgaria"))
        XCTAssertTrue(Currency.named("GBP").matches("England"))
        XCTAssertEqual(Currency.named("EUR").countryLabel(matching: "Germany"), "Germany")
        XCTAssertEqual(Currency.named("GBP").countryLabel, "United Kingdom")
        XCTAssertTrue(Currency.all.allSatisfy { !$0.countries.isEmpty })
    }

    @MainActor
    func testOfflineCacheAndFailedRefresh() async throws {
        let suite = "SimpleCurrencyTests-\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("rates.json")
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let store = ConverterStore(preferences: preferences, cacheURL: url, service: StubService(snapshot: snapshot))
        await store.refresh(force: true)
        XCTAssertNotNil(store.snapshot)
        XCTAssertFalse(store.cacheWriteFailed)
        store.source = "EUR"
        store.target = "JPY"
        store.amount = "250"
        store.toggleFavorite("XPF")
        let offline = ConverterStore(preferences: preferences, cacheURL: url, service: FailedService())
        XCTAssertEqual(offline.source, "EUR")
        XCTAssertEqual(offline.target, "JPY")
        XCTAssertEqual(offline.amount, "250")
        XCTAssertTrue(offline.favorites.contains("XPF"))
        await offline.refresh(force: true)
        XCTAssertTrue(offline.updateFailed)
        XCTAssertEqual(offline.snapshot?.fetchedAt, snapshot.fetchedAt)
        XCTAssertNotNil(offline.lastChecked)
        XCTAssertEqual(offline.snapshot?.multiplier(from: "EUR", to: "JPY"), 200)
        XCTAssertEqual(offline.result, Amount.format(50000, currency: .named("JPY")))
        offline.amount = ""
        let reopened = ConverterStore(preferences: preferences, cacheURL: url, service: FailedService())
        XCTAssertEqual(reopened.amount, "")
    }

    @MainActor
    func testSavedConversionKeepsOriginalEstimateAndPhotoAcrossReopen() async throws {
        let suite = "SimpleCurrencyTests-\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let converter = ConverterStore(preferences: preferences, cacheURL: directory.appendingPathComponent("rates.json"), service: StubService(snapshot: snapshot))
        XCTAssertNil(converter.savedDraft())
        await converter.refresh(force: true)
        converter.source = "EUR"
        converter.target = "JPY"
        converter.amount = "25"
        var draft = try XCTUnwrap(converter.savedDraft())
        draft.note = "Blue bowl at the station shop"
        let photo = Data([1, 2, 3, 4])
        let library = SavedConversions(directory: directory.appendingPathComponent("Saved"))
        try library.save(draft, photo: photo)
        converter.amount = "100"
        converter.target = "USD"
        let reopened = SavedConversions(directory: directory.appendingPathComponent("Saved"))
        let entry = try XCTUnwrap(reopened.items.first)
        XCTAssertEqual(entry.amount, 25)
        XCTAssertEqual(entry.convertedAmount, 5000)
        XCTAssertEqual(entry.target, "JPY")
        XCTAssertEqual(entry.note, draft.note)
        XCTAssertEqual(entry.rateDates, ["2026-09-24", "2026-09-25"])
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(reopened.photoURL(for: entry))), photo)
        converter.amount = "invalid"
        XCTAssertNil(converter.savedDraft())
    }

    @MainActor
    func testCorruptSavedIndexIsNotOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = directory.appendingPathComponent("conversions.json")
        let original = Data("incomplete file".utf8)
        try original.write(to: index)
        let library = SavedConversions(directory: directory)
        XCTAssertNotNil(library.loadError)
        let draft = SavedConversion(id: UUID(), savedAt: Date(), source: "USD", target: "EUR", amount: 10, multiplier: 1, convertedAmount: 10, rateDates: [], ratesCheckedAt: nil, note: "", photoFilename: nil)
        XCTAssertThrowsError(try library.save(draft, photo: nil))
        XCTAssertEqual(try Data(contentsOf: index), original)
    }

    @MainActor
    func testPartialUpdatePreservesOriginalDate() async throws {
        let suite = "SimpleCurrencyTests-\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("rates.json")
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url)
        let partial = RateSnapshot(fetchedAt: Date(), rows: [Rate(date: "2026-09-26", base: "USD", quote: "EUR", rate: 1)])
        let store = ConverterStore(preferences: preferences, cacheURL: url, service: StubService(snapshot: partial))
        await store.refresh(force: true)
        XCTAssertEqual(store.snapshot?.row("JPY")?.date, "2026-09-24")
        XCTAssertEqual(store.snapshot?.row("EUR")?.date, "2026-09-26")
    }
}

private struct StubService: RateService {
    let snapshot: RateSnapshot
    func fetch() async throws -> RateSnapshot { snapshot }
}
private struct FailedService: RateService {
    func fetch() async throws -> RateSnapshot { throw URLError(.notConnectedToInternet) }
}
