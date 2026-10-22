import Foundation
import Observation

public struct HistoryItem: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var text: String
    public var barcodes: [String]
    /// The barcode, not the text, was what landed on the clipboard; picking the item
    /// from history copies the same thing again.
    public var prefersBarcode: Bool

    public init(text: String, barcodes: [String], prefersBarcode: Bool = false) {
        self.text = text
        self.barcodes = barcodes
        self.prefersBarcode = prefersBarcode
    }

    /// History saved before `prefersBarcode` existed has no such key.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        text = try container.decode(String.self, forKey: .text)
        barcodes = try container.decode([String].self, forKey: .barcodes)
        prefersBarcode = try container.decodeIfPresent(Bool.self, forKey: .prefersBarcode) ?? false
    }

    public var isBarcode: Bool {
        text.isEmpty || (prefersBarcode && !barcodes.isEmpty)
    }

    /// What gets copied when the item is picked from the history menu.
    public var primaryContent: String {
        isBarcode ? barcodes.joined(separator: "\n") : text
    }
}

@MainActor
@Observable
public final class HistoryStore {
    public private(set) var items: [HistoryItem] = []

    private let fileURL: URL
    private let limit: Int

    public init(fileURL: URL = HistoryStore.defaultFileURL, limit: Int = 50) {
        self.fileURL = fileURL
        self.limit = max(limit, 0)
        load()
    }

    public static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("SnipText", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    public func add(_ item: HistoryItem) {
        items.removeAll { $0.text == item.text && $0.barcodes == item.barcodes }
        items.insert(item, at: 0)
        if items.count > limit {
            items.removeLast(items.count - limit)
        }
        save()
    }

    public func clear() {
        items.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        items = (try? JSONDecoder().decode([HistoryItem].self, from: data)) ?? []
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(items).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("SnipText: failed to save history: \(error)")
        }
    }
}
