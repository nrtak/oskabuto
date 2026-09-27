import SwiftUI

@main
struct SimpleCurrencyApp: App {
    @StateObject private var store = ConverterStore()
    var body: some Scene { WindowGroup { ConverterView(store: store) } }
}
