import Foundation

struct Currency: Identifiable, Hashable {
    let code: String
    let name: String
    let aliases: String
    var id: String { code }
    var symbol: String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.currencySymbol ?? code
    }
    var countries: [String] { Self.countryNames[code] ?? [] }
    var countryLabel: String {
        if countries.count <= 2 { return countries.joined(separator: " · ") }
        return "\(countries[0]) · \(countries[1]) & more"
    }
    func countryLabel(matching query: String) -> String {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return countryLabel }
        let matches = countries.filter { $0.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        return matches.isEmpty ? countryLabel : matches.joined(separator: " · ")
    }
    var fractionDigits: Int { ["JPY", "KRW", "VND", "XPF"].contains(code) ? 0 : 2 }

    func matches(_ query: String) -> Bool {
        let terms = query.split(whereSeparator: { $0.isWhitespace })
        let text = "\(code) \(name) \(aliases) \(countries.joined(separator: " "))"
        return terms.allSatisfy { text.range(of: String($0), options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    static func named(_ code: String) -> Currency { all.first { $0.code == code } ?? all[0] }
    static let countryNames: [String: [String]] = [
        "USD": ["United States"], "CAD": ["Canada"], "MXN": ["Mexico"],
        "EUR": ["Germany", "France", "Austria", "Belgium", "Bulgaria", "Croatia", "Cyprus", "Estonia", "Finland", "Greece", "Ireland", "Italy", "Latvia", "Lithuania", "Luxembourg", "Malta", "Netherlands", "Portugal", "Slovakia", "Slovenia", "Spain", "Andorra", "Monaco", "San Marino", "Vatican City", "Montenegro", "Kosovo"],
        "JPY": ["Japan"], "TWD": ["Taiwan"], "KRW": ["South Korea"],
        "HKD": ["Hong Kong"], "CNY": ["Mainland China"], "VND": ["Vietnam"],
        "GBP": ["United Kingdom"], "AED": ["United Arab Emirates"],
        "QAR": ["Qatar"], "SAR": ["Saudi Arabia"], "ILS": ["Israel"],
        "XPF": ["French Polynesia", "New Caledonia", "Wallis and Futuna"],
        "FJD": ["Fiji"], "BRL": ["Brazil"], "AUD": ["Australia"],
        "NZD": ["New Zealand"], "CHF": ["Switzerland", "Liechtenstein"],
        "SGD": ["Singapore"], "THB": ["Thailand"], "INR": ["India"],
        "PHP": ["Philippines"], "IDR": ["Indonesia"]
    ]
    static let all: [Currency] = [
        .init(code: "USD", name: "US dollar", aliases: "USA United States America"),
        .init(code: "CAD", name: "Canadian dollar", aliases: "Canada"),
        .init(code: "MXN", name: "Mexican peso", aliases: "Mexico México"),
        .init(code: "EUR", name: "Euro", aliases: "Europe Eurozone Croatia France Germany Italy Spain Portugal Austria Belgium Netherlands Ireland Greece Finland"),
        .init(code: "JPY", name: "Japanese yen", aliases: "Japan"),
        .init(code: "TWD", name: "New Taiwan dollar", aliases: "Taiwan"),
        .init(code: "KRW", name: "South Korean won", aliases: "South Korea"),
        .init(code: "HKD", name: "Hong Kong dollar", aliases: "Hong Kong"),
        .init(code: "CNY", name: "Chinese yuan", aliases: "Mainland China RMB renminbi"),
        .init(code: "VND", name: "Vietnamese dong", aliases: "Vietnam Việt Nam"),
        .init(code: "GBP", name: "Pound sterling", aliases: "United Kingdom UK Britain England Scotland Wales Northern Ireland"),
        .init(code: "AED", name: "UAE dirham", aliases: "United Arab Emirates Dubai Abu Dhabi"),
        .init(code: "QAR", name: "Qatari riyal", aliases: "Qatar"),
        .init(code: "SAR", name: "Saudi riyal", aliases: "Saudi Arabia"),
        .init(code: "ILS", name: "Israeli new shekel", aliases: "Israel"),
        .init(code: "XPF", name: "CFP franc", aliases: "French Polynesia Tahiti Bora Bora New Caledonia Wallis Futuna"),
        .init(code: "FJD", name: "Fiji dollar", aliases: "Fiji"),
        .init(code: "BRL", name: "Brazilian real", aliases: "Brazil Brasil"),
        .init(code: "AUD", name: "Australian dollar", aliases: "Australia"),
        .init(code: "NZD", name: "New Zealand dollar", aliases: "New Zealand"),
        .init(code: "CHF", name: "Swiss franc", aliases: "Switzerland Liechtenstein"),
        .init(code: "SGD", name: "Singapore dollar", aliases: "Singapore"),
        .init(code: "THB", name: "Thai baht", aliases: "Thailand"),
        .init(code: "INR", name: "Indian rupee", aliases: "India"),
        .init(code: "PHP", name: "Philippine peso", aliases: "Philippines"),
        .init(code: "IDR", name: "Indonesian rupiah", aliases: "Indonesia Bali")
    ]
}
