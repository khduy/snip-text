import Foundation
import Observation

public struct HistoryItem: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var text: String
    public var barcodes: [String]

    public init(text: String, barcodes: [String]) {
        self.text = text
        self.barcodes = barcodes
    }

    /// What gets copied when the item is picked from the history menu.
    public var primaryContent: String {
        text.isEmpty ? barcodes.joined(separator: "\n") : text
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
        self.limit = limit
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
