import Carbon.HIToolbox
import KeyboardShortcuts
import Observation

/// Whether the capture shortcut really reached the system. When another app already holds the
/// combination, KeyboardShortcuts only prints Carbon's error and still counts the shortcut as
/// registered, so it never tries again. This checks for itself, and each check re-registers.
@MainActor
@Observable
final class HotkeyStatus {
    static let shared = HotkeyStatus()

    private(set) var isTaken = false

    private init() {
        // Posted by KeyboardShortcuts when the Recorder sets a new shortcut; the name is internal there.
        NotificationCenter.default.addObserver(
            forName: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"), object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { HotkeyStatus.shared.refresh() }
        }
    }

    func refresh() {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: .capture) else {
            isTaken = false
            return
        }
        // Drop SnipText's own registration first, or the probe would collide with it.
        KeyboardShortcuts.disable(.capture)
        isTaken = !Self.canRegister(shortcut)
        KeyboardShortcuts.enable(.capture)
    }

    private static func canRegister(_ shortcut: KeyboardShortcuts.Shortcut) -> Bool {
        var hotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.carbonKeyCode), UInt32(shortcut.carbonModifiers),
            EventHotKeyID(signature: 0x534E_5054, id: 1), // "SNPT"
            GetEventDispatcherTarget(), 0, &hotKey)
        guard status == noErr, let hotKey else { return false }
        UnregisterEventHotKey(hotKey)
        return true
    }
}
