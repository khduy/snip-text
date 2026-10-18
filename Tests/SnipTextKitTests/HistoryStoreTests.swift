import Foundation
import Testing
@testable import SnipTextKit

@MainActor
@Suite struct HistoryStoreTests {
    private let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sniptext-tests-\(UUID().uuidString)/history.json")

    @Test func persistsAcrossInstances() {
        let store = HistoryStore(fileURL: fileURL)
        store.add(HistoryItem(text: "một", barcodes: []))
        store.add(HistoryItem(text: "", barcodes: ["QR"]))

        let reloaded = HistoryStore(fileURL: fileURL)
        #expect(reloaded.items.map(\.primaryContent) == ["QR", "một"])
    }

    @Test func dedupesAndCapsAtLimit() {
        let store = HistoryStore(fileURL: fileURL, limit: 3)
        for text in ["a", "b", "c", "d", "b"] {
            store.add(HistoryItem(text: text, barcodes: []))
        }
        #expect(store.items.map(\.text) == ["b", "d", "c"])
    }

    @Test func clearRemovesEverything() {
        let store = HistoryStore(fileURL: fileURL)
        store.add(HistoryItem(text: "x", barcodes: []))
        store.clear()
        #expect(HistoryStore(fileURL: fileURL).items.isEmpty)
    }
}
