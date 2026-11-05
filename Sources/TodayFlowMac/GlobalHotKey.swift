#if canImport(AppKit)
import AppKit
import Carbon
import Foundation

/// A system-wide hotkey (driver.md FR-05: default ⌃⌥Space opens capture).
///
/// Uses the Carbon Hot Key API rather than a global `NSEvent` monitor: it works
/// while another app is frontmost and does not require Accessibility
/// permission. Registration is best-effort — if the shortcut is already taken
/// (or the OS rejects it), `isRegistered` stays false and the rest of the app
/// keeps working.
@MainActor
public final class GlobalHotKey {
    /// ⌃⌥Space, the driver's default capture shortcut. `0x31` is the virtual
    /// key code for Space (`kVK_ANSI_Space`; the Carbon submodule that exports
    /// it is not importable on every SDK).
    public static let defaultKeyCode: UInt32 = 0x31
    public static let defaultModifiers = UInt32(controlKey | optionKey)

    /// Four-character signature `TFHK` plus id 1 identify our hotkey.
    private nonisolated static let signature: FourCharCode = 0x5446_484B
    private nonisolated static let identifier: UInt32 = 1

    private let action: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    public private(set) var isRegistered = false

    /// Creates the hotkey and registers it immediately with the defaults.
    public init(action: @escaping @MainActor () -> Void) {
        self.action = action
        isRegistered = register()
    }

    /// Registers (or re-registers) the hotkey. Returns false when either the
    /// event handler or the hotkey itself could not be installed.
    @discardableResult
    public func register(
        keyCode: UInt32 = GlobalHotKey.defaultKeyCode,
        modifiers: UInt32 = GlobalHotKey.defaultModifiers
    ) -> Bool {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        guard handlerStatus == noErr else {
            eventHandlerRef = nil
            return false
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        let hotKeyStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard hotKeyStatus == noErr else {
            if let eventHandlerRef {
                RemoveEventHandler(eventHandlerRef)
            }
            eventHandlerRef = nil
            hotKeyRef = nil
            return false
        }

        isRegistered = true
        return true
    }

    /// Removes the hotkey and its event handler. Safe to call more than once.
    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        hotKeyRef = nil
        eventHandlerRef = nil
        isRegistered = false
    }

    // MARK: - Carbon callback

    /// The C callback runs on the main run loop; hop onto the main actor to
    /// invoke the user action.
    private nonisolated static let eventHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr,
              hotKeyID.signature == GlobalHotKey.signature,
              hotKeyID.id == GlobalHotKey.identifier
        else {
            return OSStatus(eventNotHandledErr)
        }

        let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
        MainActor.assumeIsolated {
            hotKey.action()
        }
        return noErr
    }
}
#endif
