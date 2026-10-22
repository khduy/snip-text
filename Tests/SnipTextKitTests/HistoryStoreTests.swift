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

    @Test func keepsPreferredBarcode() {
        let store = HistoryStore(fileURL: fileURL)
        store.add(HistoryItem(text: "chữ", barcodes: ["QR"], prefersBarcode: true))
        let item = HistoryStore(fileURL: fileURL).items[0]
        #expect(item.isBarcode)
        #expect(item.primaryContent == "QR")
    }

    @Test func readsHistoryWithoutPreference() throws {
        let json = #"[{"id":"7E57D004-2B97-4E7A-B45A-5A3D2D2E1A11","date":0,"text":"a","barcodes":["QR"]}]"#
        let items = try JSONDecoder().decode([HistoryItem].self, from: Data(json.utf8))
        #expect(items[0].primaryContent == "a")
    }

    @Test func nonPositiveLimitKeepsNothing() {
        let store = HistoryStore(fileURL: fileURL, limit: -1)
        store.add(HistoryItem(text: "x", barcodes: []))
        #expect(store.items.isEmpty)
    }
}
