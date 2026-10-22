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
    /// An unreadable history file was moved aside and is still there; `clear()` removes it.
    public private(set) var hasUnreadableFile = false

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

    /// Also removes a history file moved aside as unreadable: it holds older captures too.
    public func clear() {
        items.removeAll()
        save()
        try? FileManager.default.removeItem(at: unreadableFileURL)
        // From the disk, not assumed: if the delete failed, the menu keeps offering it.
        hasUnreadableFile = FileManager.default.fileExists(atPath: unreadableFileURL.path)
    }

    /// Where an unreadable history file is moved, so the next save does not overwrite it.
    public var unreadableFileURL: URL {
        fileURL.deletingPathExtension().appendingPathExtension("unreadable.json")
    }

    private func load() {
        // Checked on every launch: the file can be left from one before, with no history.json now.
        defer { hasUnreadableFile = FileManager.default.fileExists(atPath: unreadableFileURL.path) }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            items = try JSONDecoder().decode([HistoryItem].self, from: data)
        } catch {
            NSLog("SnipText: history unreadable, moved aside: \(error)")
            try? FileManager.default.removeItem(at: unreadableFileURL)
            try? FileManager.default.moveItem(at: fileURL, to: unreadableFileURL)
        }
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
