import Foundation
import KeyboardShortcuts
import SnipTextKit

extension KeyboardShortcuts.Name {
    static let capture = Self("capture", default: .init(.two, modifiers: [.command, .shift]))
}

/// UserDefaults keys shared by `@AppStorage` in views and by `AppController`.
enum PrefKey {
    static let lineBreakMode = "lineBreakMode"
    static let preferBarcode = "preferBarcode"
    static let showMenuBarIcon = "showMenuBarIcon"
}

extension UserDefaults {
    /// `bool(forKey:)` reads a missing key as false; this lets a default-on setting say so.
    func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        object(forKey: key) == nil ? defaultValue : bool(forKey: key)
    }
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
