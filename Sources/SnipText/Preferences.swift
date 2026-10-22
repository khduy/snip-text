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
    static let freezeScreen = "freezeScreen"
    static let saveHistory = "saveHistory"
    /// No UI: `defaults write io.github.khduy.sniptext saveLastCapture -bool true`.
    static let saveLastCapture = "saveLastCapture"
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

    /// On: the selection is drawn over a snapshot taken when the hotkey is pressed.
    /// Off: the screen stays live under the overlay and the region is captured after the drag.
    static var freezeScreen: Bool {
        UserDefaults.standard.bool(forKey: PrefKey.freezeScreen)
    }

    /// On by default. Off: new captures are copied but not recorded; what is already there stays
    /// until "Xoá lịch sử".
    static var saveHistory: Bool {
        UserDefaults.standard.bool(forKey: PrefKey.saveHistory, default: true)
    }

    /// Off by default: the image can hold anything that was on screen.
    static var saveLastCapture: Bool {
        UserDefaults.standard.bool(forKey: PrefKey.saveLastCapture)
    }
}

extension LineBreakMode {
    var title: String {
        switch self {
        case .keepLines: "Giữ nguyên xuống dòng"
        case .mergeParagraphs: "Gộp thành đoạn văn"
        case .preserveIndent: "Giữ thụt lề (cho code)"
        }
    }
}
