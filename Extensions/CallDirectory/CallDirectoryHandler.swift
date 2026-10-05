import CallKit

final class CallDirectoryHandler: CXCallDirectoryProvider {
    override func beginRequest(with context: CXCallDirectoryExtensionContext) {
        do {
            let entries = try CallStore.read().filter { $0.number > 0 }.sorted { $0.number < $1.number }
            if context.isIncremental {
                context.removeAllBlockingEntries()
                context.removeAllIdentificationEntries()
            }
            for entry in entries where entry.blocked { context.addBlockingEntry(withNextSequentialPhoneNumber: entry.number) }
            for entry in entries where !entry.blocked { context.addIdentificationEntry(withNextSequentialPhoneNumber: entry.number, label: entry.label) }
            context.completeRequest()
        } catch { context.cancelRequest(withError: error) }
    }
}
