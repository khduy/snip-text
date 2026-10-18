import Foundation
import KeyboardShortcuts
import SnipTextKit

extension KeyboardShortcuts.Name {
    static let capture = Self("capture", default: .init(.two, modifiers: [.command, .shift]))
    // ⇧⌘3, ⇧⌘4 and ⇧⌘5 belong to macOS screenshots, so stay on the 2 key.
    static let recapture = Self("recapture", default: .init(.two, modifiers: [.command, .shift, .option]))
}

/// UserDefaults keys shared by `@AppStorage` in views and by `AppController`.
enum PrefKey {
    static let lineBreakMode = "lineBreakMode"
    static let preferBarcode = "preferBarcode"
}

enum Preferences {
    static var lineBreakMode: LineBreakMode {
        UserDefaults.standard.string(forKey: PrefKey.lineBreakMode).flatMap(LineBreakMode.init) ?? .keepLines
    }

    static var preferBarcode: Bool {
        UserDefaults.standard.bool(forKey: PrefKey.preferBarcode)
    }
}

extension LineBreakMode {
    var title: String {
        switch self {
        case .keepLines: "Giữ nguyên xuống dòng"
        case .mergeParagraphs: "Gộp thành đoạn văn"
        }
    }
}
